import Foundation
import GRDB
import Testing
@testable import LifeCore

@Suite struct TurnValidationTests {
    @Test(arguments: ["omitted", "null", "empty", "whitespace"], [LLMNarrator.Mode.singleCall, .twoStep])
    func universityLettersAreNotACrime(_ representation: String, _ mode: LLMNarrator.Mode) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/narration/university-letter.json"))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var resolution = try #require(json["resolution"] as? [String: Any])
        switch representation {
        case "omitted": resolution.removeValue(forKey: "crime_attempt")
        case "empty": resolution["crime_attempt"] = ["reason": ""]
        case "whitespace": resolution["crime_attempt"] = ["reason": " \n\t "]
        default: break
        }
        json["resolution"] = resolution
        let reply = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
        let replies = mode == .twoStep ? [StubProvider.reply("Your father offers you the first letter."), StubProvider.reply(reply)] : [StubProvider.reply(reply)]
        let provider = StubProvider(responses: replies)
        // Exercise both the structured-output path and the local unconstrained extraction path.
        provider.capabilities.supportsJSONSchema = mode == .singleCall
        let character = NewCharacter(name: "Richard", birthplace: "Texas, USA", birthYear: 1985,
            appearance: "180cm, nerdy", startingAge: 18, background: "Wealthy family", familyWealthTier: .wealthy)
        let store = try TestChat.library().createChat(character: character, economy: .sampleUS2005).store
        let before = try store.revision()
        let processor = TurnProcessor(store: store, narrator: LLMNarrator(provider: provider, mode: mode), fate: FixedFate([42]))
        let result = try await processor.play("I run downstairs to open my university letters with my father.")
        #expect(!result.repaired && result.rejections.isEmpty)
        #expect(provider.requests.count == (mode == .twoStep ? 2 : 1))
        #expect(result.text == json["narration"] as? String)
        #expect(try store.character().currentDate == GameDate(year: 2003, month: 1, day: 1))
        #expect(try store.balanceMinor() == 175_000)
        #expect(try store.ledger(limit: 10).count == 1)
        #expect(try store.lifeState()["legal_status"] == nil)
        #expect(try store.lifeState()["_engine_last_crime_date"] == nil)
        #expect(try store.lifeState()["education"] == "Reviewing university offers")
        #expect(try store.castMembers().map(\.name) == ["Daniel"])
        #expect(try store.decisions(limit: 10).count == 1)
        #expect(try store.events().map(\.title) == ["The university letters arrive"])
        #expect(try store.authorNotes() == json["author_notes"] as? String)
        #expect(try store.choices() == ["I open the first letter."])
        #expect(try store.revision() == before + 1)
    }

    @Test func crimeSchemaAllowsAnExplicitNoAction() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(OutputSchema.json.utf8)) as? [String: Any])
        let properties = try #require(json["properties"] as? [String: Any])
        let resolution = try #require(properties["resolution"] as? [String: Any])
        let fields = try #require(resolution["properties"] as? [String: Any])
        let crime = try #require(fields["crime_attempt"] as? [String: Any])
        #expect(crime["type"] as? [String] == ["object", "null"])
        #expect(!(resolution["required"] as? [String] ?? []).contains("crime_attempt"))
    }

    @Test(arguments: [false, true])
    func failedTurnLeavesEveryStoredTableUnchanged(_ repairNetworkFailure: Bool) async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        var existing = TestChat.turn(narration: "A previous chapter.", streamChanges: [
            IncomeStreamChange(action: .start, name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000)])
        existing.authorNotes = "An existing memory."; existing.choices = ["Keep working."]
        try store.apply(existing)
        let before = try contents(store)
        // Valid payroll, purchases, crime consequences, paths and memories must all be rolled back
        // when a separate proposal remains invalid after the repair.
        var proposed = output("An invalid ending.", time: TimeAdvance(unit: .months, amount: 1),
            money: [ProposedMoneyEntry(sourceType: .sideHustle, amountMinor: 20_000_000_000, reason: "An impossible sale")],
            streams: [IncomeStreamChange(action: .end, name: "Shop", kind: nil, tier: nil, monthlyMinor: nil)],
            decisions: [DecisionRecord(summary: "Leave work", choice: "Quit", importance: .major)],
            lifeState: [LifeStateChange(key: "residence", value: "Elsewhere")],
            cast: [CastUpdate(name: "New person", relation: "friend", notes: nil, status: "alive")],
            events: [EventRecord(title: "A change", importance: .major, uncanny: false)])
        proposed.resolution.financialActions = [.init(action: .buyAsset, id: "bike", name: "Bicycle", amountMinor: 10_000)]
        proposed.resolution.pathUpdates = [.init(id: "shop", title: "A shop", stage: .idea)]
        proposed.resolution.threadUpdates = [.init(id: "question", title: "A question", notes: "Unresolved")]
        proposed.resolution.crimeAttempt = CrimeAttempt(reason: "An impulsive offense")
        proposed.resolution.lifeEnded = true
        proposed.authorNotes = "New notes"; proposed.choices = ["A new choice"]
        let repair: ScriptedNarrator.Step = repairNetworkFailure ? .error(ProviderError.http(status: 503, body: "unavailable")) : .output(proposed)
        let narrator = ScriptedNarrator(narrate: [.output(proposed)], repair: [repair])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([75]))
        do { _ = try await processor.play("I try something new."); Issue.record("Expected a rejected turn") }
        catch TurnError.validationFailed(let reasons) {
            #expect(reasons.contains { $0.contains("bound") })
            #expect(reasons.contains { $0.contains("Repair failed") } == repairNetworkFailure)
        }
        #expect(try contents(store) == before)
        #expect(narrator.narrateCalls == 1 && narrator.repairCalls == 1)
    }

    @Test func rejectedResponsesStillCountTowardUsage() async throws {
        var bad = output("An unusable reply.")
        bad.resolution.crimeAttempt = CrimeAttempt(reason: String(repeating: "x", count: 501))
        let json = String(decoding: try OutputCoding.encoder.encode(bad), as: UTF8.self)
        let provider = StubProvider(responses: [StubProvider.reply(json), StubProvider.reply(json)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tracker = try UsageTracker(url: folder.appendingPathComponent("usage.json"))
        let metered = MeteredProvider(base: provider, tracker: tracker, providerName: "fixture", model: "fixture",
            inputUSDPerMillion: 1, outputUSDPerMillion: 2, dailyLimit: 1)
        let store = try TestChat.chat(try TestChat.library()).store
        let processor = TurnProcessor(store: store, narrator: LLMNarrator(provider: metered), fate: FixedFate([42]))
        await #expect(throws: TurnError.self) { _ = try await processor.play("I open a letter.") }
        #expect(await tracker.history().count == 2)
        #expect(await tracker.todayCost() == 0.004)
        #expect(try store.messageCount() == 0)
        #expect(try store.turnLogs().isEmpty)
    }

    private func contents(_ store: LifeStore) throws -> [String: [String]] {
        try store.dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            var result: [String: [String]] = [:]
            for table in tables {
                let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
                result[table] = try Row.fetchAll(db, sql: "SELECT * FROM \"\(quoted)\"").map(\.description).sorted()
            }
            return result
        }
    }
}
