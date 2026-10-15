import XCTest
@testable import LifeGPTCore

/// Returns canned replies in order and records every request it received.
final class MockProvider: LLMProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String]
    private(set) var requests: [LLMRequest] = []

    init(replies: [String]) { self.replies = replies }

    func complete(_ request: LLMRequest) async throws -> String {
        lock.withLock {
            requests.append(request)
            return replies.isEmpty ? "summary" : replies.removeFirst()
        }
    }
}

func makeState() -> GameState {
    GameState(
        character: PlayerCharacter(name: "Ada Lovell", gender: "female", birthDate: GameDate(year: 1962, month: 4), birthplace: "Leeds, England"),
        world: World(currentDate: GameDate(year: 1962, month: 4), location: "Leeds, England", currency: "GBP")
    )
}

func encode(_ result: TurnResult) -> String {
    String(data: try! JSONEncoder().encode(result), encoding: .utf8)!
}

final class GameDateTests: XCTestCase {
    func testNormalizesAndAdds() {
        XCTAssertEqual(GameDate(year: 2000, month: 13), GameDate(year: 2001, month: 1))
        XCTAssertEqual(GameDate(year: 2000, month: 0), GameDate(year: 1999, month: 12))
        XCTAssertEqual(GameDate(year: 2000, month: 11).adding(months: 3), GameDate(year: 2001, month: 2))
    }

    func testAge() {
        let born = GameDate(year: 1990, month: 6)
        XCTAssertEqual(born.yearsUntil(GameDate(year: 2000, month: 5)), 9)
        XCTAssertEqual(born.yearsUntil(GameDate(year: 2000, month: 6)), 10)
    }
}

final class StateApplierTests: XCTestCase {
    func testAppliesDeltasClampsAndAccrues() {
        var state = makeState()
        state.finances = Finances(cash: 1000, annualIncome: 24000, annualExpenses: 12000)
        state.stats.health = 95
        let result = TurnResult(
            narration: "A year passes.",
            monthsElapsed: 12,
            statChanges: .init(health: 20, happiness: -5),
            financeChanges: .init(oneOffCash: -200, annualIncomeChange: 6000),
            newOccupation: "Typist",
            relationshipChanges: [.init(name: "Mary", relation: "mother", closenessChange: 30, note: "Proud of you.")],
            timelineEntries: [.init(title: "First job", summary: "Started typing.", importance: 9)],
            choices: ["Ask for a raise", "", "Go dancing"]
        )
        let record = StateApplier.apply(result, playerAction: "Work hard", to: &state)

        XCTAssertEqual(state.world.currentDate, GameDate(year: 1963, month: 4))
        XCTAssertEqual(state.stats.health, 100)
        XCTAssertEqual(state.stats.happiness, 65)
        XCTAssertEqual(state.finances.cash, 1000 + 12000 - 200, accuracy: 0.001)
        XCTAssertEqual(state.finances.annualIncome, 30000)
        XCTAssertEqual(state.character.occupation, "Typist")
        XCTAssertEqual(state.relationships.first?.closeness, 80)
        XCTAssertEqual(state.timeline.first?.importance, 5)
        XCTAssertEqual(state.pendingChoices, ["Ask for a raise", "Go dancing"])
        XCTAssertEqual(state.turns.count, 1)
        XCTAssertFalse(record.changeLog.isEmpty)
    }

    func testUpdatesExistingRelationshipAndTimeNeverGoesBackwards() {
        var state = makeState()
        state.relationships = [Relationship(name: "Mary", relation: "mother", closeness: 50)]
        StateApplier.apply(
            TurnResult(narration: "", monthsElapsed: -5, relationshipChanges: [.init(name: "mary", relation: "", closenessChange: -10, status: "deceased")]),
            playerAction: "x", to: &state
        )
        XCTAssertEqual(state.world.currentDate, GameDate(year: 1962, month: 4))
        XCTAssertEqual(state.relationships.count, 1)
        XCTAssertEqual(state.relationships[0].closeness, 40)
        XCTAssertEqual(state.relationships[0].relation, "mother")
        XCTAssertEqual(state.relationships[0].status, .deceased)
    }

    func testDeath() {
        var state = makeState()
        StateApplier.apply(TurnResult(narration: "The end.", monthsElapsed: 1, choices: ["a"], died: true, causeOfDeath: "Pneumonia"), playerAction: "x", to: &state)
        XCTAssertTrue(state.isDead)
        XCTAssertEqual(state.causeOfDeath, "Pneumonia")
        XCTAssertTrue(state.pendingChoices.isEmpty)
    }
}

final class TurnResultTests: XCTestCase {
    func testDecodesThroughCodeFences() throws {
        let json = encode(TurnResult(narration: "Hi", monthsElapsed: 2))
        let decoded = try TurnResult.decode(from: "```json\n\(json)\n```")
        XCTAssertEqual(decoded.narration, "Hi")
        XCTAssertEqual(decoded.monthsElapsed, 2)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try TurnResult.decode(from: "no json here"))
    }

    func testSchemaRequiresEveryProperty() throws {
        let schema = TurnResult.jsonSchema
        let props = try XCTUnwrap(schema["properties"])
        guard case .object(let p) = props, case .array(let req)? = schema["required"] else { return XCTFail() }
        XCTAssertEqual(Set(p.keys), Set(req.compactMap(\.stringValue)))
        XCTAssertEqual(schema["additionalProperties"], .bool(false))
    }
}

final class PromptAssemblerTests: XCTestCase {
    func testIncludesSavedStateEraAndAction() {
        var state = makeState()
        state.world.currentDate = GameDate(year: 1985, month: 1)
        state.finances.cash = 1234
        state.relationships = [Relationship(name: "Tom", relation: "brother", closeness: 70)]
        state.timeline = [TimelineEntry(date: GameDate(year: 1980, month: 1), title: "Moved to London", summary: "New flat.", importance: 4)]
        let prompt = PromptAssembler().assemble(state: state, playerAction: "Buy a computer", directive: EventDirective(category: "money", intensity: "minor"))

        XCTAssertTrue(prompt.user.contains("Ada Lovell"))
        XCTAssertTrue(prompt.user.contains("Age: 22"))
        XCTAssertTrue(prompt.user.contains("$1,234"))
        XCTAssertTrue(prompt.user.contains("Tom, brother"))
        XCTAssertTrue(prompt.user.contains("Moved to London"))
        XCTAssertTrue(prompt.user.contains("1980s"))
        XCTAssertTrue(prompt.user.contains("category: money"))
        XCTAssertTrue(prompt.user.hasSuffix("Buy a computer"))
        XCTAssertEqual(prompt.system, PromptAssembler.systemPrompt)
    }

    func testTrimsToBudgetButKeepsLifeDefiningMoments() {
        var state = makeState()
        for i in 0..<40 {
            state.timeline.append(TimelineEntry(date: state.world.currentDate, title: "Minor \(i)", summary: String(repeating: "x", count: 200), importance: 1))
        }
        state.timeline.append(TimelineEntry(date: state.world.currentDate, title: "Married Tom", summary: "", importance: 5))
        for i in 0..<8 {
            state.turns.append(TurnRecord(dateBefore: state.world.currentDate, dateAfter: state.world.currentDate, playerAction: "a\(i)", narration: String(repeating: "y", count: 500), events: [], changeLog: []))
        }
        let assembler = PromptAssembler(budget: .init(maxCharacters: 4_000, recentTurns: 8, minRecentTurns: 2))
        let prompt = assembler.assemble(state: state, playerAction: "Go", directive: nil)

        XCTAssertLessThanOrEqual(prompt.user.count, 4_000)
        XCTAssertTrue(prompt.user.contains("Married Tom"))
        XCTAssertTrue(prompt.user.contains("a7"))
    }
}

final class HistoryCompactorTests: XCTestCase {
    func testFoldsOldTurnsAndMergesChapters() async throws {
        var state = makeState()
        for i in 0..<20 {
            state.turns.append(TurnRecord(dateBefore: GameDate(year: 1962 + i, month: 1), dateAfter: GameDate(year: 1963 + i, month: 1), playerAction: "a\(i)", narration: "n\(i)", events: [], changeLog: []))
        }
        let compactor = HistoryCompactor(keepRecent: 4, batchSize: 4, maxChapters: 2, chapterMergeCount: 2)
        XCTAssertTrue(compactor.needsCompaction(state))
        let provider = MockProvider(replies: [])
        try await compactor.compact(&state, using: provider)

        // 20 turns, keep 4 recent: 4 batches of 4 folded -> 4 chapters, merged down to <= 2.
        XCTAssertEqual(state.firstUnsummarizedTurn, 16)
        XCTAssertEqual(state.unsummarizedTurns.count, 4)
        XCTAssertLessThanOrEqual(state.chapters.count, 2)
        XCTAssertEqual(state.chapters.first?.from, GameDate(year: 1962, month: 1))
        XCTAssertFalse(compactor.needsCompaction(state))
        XCTAssertTrue(provider.requests[0].user.contains("a0"))
    }
}

final class EngineTests: XCTestCase {
    func testPlaysTurnAndSaves() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SaveStore(directory: dir)
        let reply = encode(TurnResult(
            narration: "You are born.", monthsElapsed: 6,
            relationshipChanges: [.init(name: "Mary", relation: "mother", closenessChange: 40)],
            choices: ["Cry", "Sleep", "Smile"]
        ))
        let provider = MockProvider(replies: [reply])
        let engine = GameEngine(provider: provider, store: store, roller: EventRoller(chance: 0))

        let (state, record) = try await engine.playTurn(GameEngine.openingAction, on: makeState())

        XCTAssertEqual(record.narration, "You are born.")
        XCTAssertEqual(state.pendingChoices.count, 3)
        XCTAssertNotNil(provider.requests.first?.jsonSchema)
        let reloaded = try store.load(state.id)
        XCTAssertEqual(reloaded.turns, state.turns)
        XCTAssertEqual(reloaded.relationships, state.relationships)
        XCTAssertEqual(reloaded.world, state.world)
        XCTAssertEqual(store.loadAll().count, 1)
    }

    func testDeadCharacterCannotPlay() async {
        var state = makeState()
        state.isDead = true
        let engine = GameEngine(provider: MockProvider(replies: []), store: SaveStore(directory: FileManager.default.temporaryDirectory))
        do {
            _ = try await engine.playTurn("x", on: state)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? LifeGPTError, .characterIsDead)
        }
    }

    func testAnthropicBodyAndResponseParsing() throws {
        let body = AnthropicProvider.body(for: LLMRequest(system: "s", user: "u", jsonSchema: TurnResult.jsonSchema), model: "claude-opus-5-5")
        XCTAssertEqual(body["model"], "claude-opus-5-5")
        XCTAssertEqual(body["output_config"]?["format"]?["type"], "json_schema")

        let ok = #"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"a\":1}"}]}"#
        XCTAssertEqual(try AnthropicProvider.text(fromResponse: Data(ok.utf8)), #"{"a":1}"#)

        let refused = #"{"stop_reason":"refusal","content":[]}"#
        XCTAssertThrowsError(try AnthropicProvider.text(fromResponse: Data(refused.utf8)))
    }
}
