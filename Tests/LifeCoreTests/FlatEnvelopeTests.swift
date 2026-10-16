import Foundation
import Testing
@testable import LifeCore

@Suite struct FlatEnvelopeTests {
    private func envelope(_ output: TurnOutput) throws -> String {
        try envelope(resolution: String(decoding: OutputCoding.encoder.encode(output.resolution), as: UTF8.self),
                     narration: output.narration, notes: output.authorNotes ?? "", choices: output.choices ?? [])
    }
    private func envelope(resolution: String, narration: String = "You act.", notes: String = "", choices: [String] = []) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["resolution": resolution, "narration": narration,
            "author_notes": notes, "choices": choices]), as: UTF8.self)
    }
    private func provider(_ replies: [String]) -> StubProvider {
        var capabilities = StubProvider.capable
        capabilities.prefersFlatResponseSchema = true
        return StubProvider(capabilities: capabilities, responses: replies.map { StubProvider.reply($0) })
    }

    @Test(arguments: [LLMNarrator.Mode.singleCall, .twoStep])
    func recordsBusinessIncomeAndPaysOnceUsingTheFlatTransport(_ mode: LLMNarrator.Mode) async throws {
        let store = try TestChat.chat(TestChat.library()).store
        var settings = SessionSettings(); settings.playStyle = .sandbox; settings.household = .familySupported
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        var start = output("Your \"video\" site earns $50,000 per month.\nThe account is ready.", streams: [
            .init(action: .start, name: "Website profit", kind: .business, tier: nil, monthlyMinor: 5_000_000,
                  accountId: "vidshare", effectiveFrom: TestChat.date.iso, reason: "Subscriptions after operating costs")])
        start.resolution.accountOpenings = [.init(id: "vidshare", name: "Richard's \"video\" site", kind: .business)]
        start.authorNotes = "Keep the monthly rate; café meeting next week."
        start.choices = ["Review the accounts."]
        let skip = output("Three months pass.", time: .init(unit: .months, amount: 3))
        var replies = [String]()
        for proposed in [start, skip] {
            if mode == .twoStep { replies.append(proposed.narration) }
            replies.append(try envelope(proposed))
        }
        let provider = provider(replies)
        let processor = TurnProcessor(store: store, narrator: LLMNarrator(provider: provider, mode: mode), fate: FixedFate([50, 50]))
        let first = try await processor.play("My website earns $50,000 net monthly profit in its business account.")
        #expect(first.text == start.narration && !first.repaired)
        #expect(try store.authorNotes() == start.authorNotes && store.choices() == start.choices)
        #expect(try store.accounts().first { $0.id == "vidshare" }?.balanceMinor == 0)
        _ = try await processor.play("Skip three months.", skipTime: .init(unit: .months, amount: 3))
        #expect(try store.accounts().first { $0.id == "vidshare" }?.balanceMinor == 15_000_000)
        #expect(try store.accounts().first { $0.id == "personal" }?.balanceMinor == 175_000)
        #expect(try store.turnLogs().count == 2 && store.ledger(limit: 20).filter { $0.sourceType == .businessProfit }.count == 3)
        #expect(provider.requests.count == (mode == .twoStep ? 4 : 2))
        for request in provider.requests where request.jsonSchema != nil {
            #expect(request.jsonSchema == OutputSchema.flatEnvelopeJSON)
            #expect(request.user.contains(OutputSchema.json) && request.user.contains(OutputSchema.flatEnvelopeInstructions))
        }
    }

    @Test(arguments: ["not JSON", "{}", "null", "[]"])
    func invalidInnerResolutionCannotCommit(_ payload: String) async throws {
        let store = try TestChat.chat(TestChat.library()).store
        let revision = try store.revision(), balance = try store.balanceMinor()
        let bad = try envelope(resolution: payload)
        let provider = provider([bad, bad])
        await #expect(throws: TurnError.self) {
            _ = try await TurnProcessor(store: store, narrator: LLMNarrator(provider: provider), fate: FixedFate([50])).play("I look around.")
        }
        #expect(provider.requests.count == 2)
        #expect(try store.revision() == revision && store.balanceMinor() == balance)
        #expect(try store.recentMessages(limit: 20).isEmpty)
    }

    @Test func invalidFinancialPayloadStillUsesAtomicValidation() async throws {
        let store = try TestChat.chat(TestChat.library()).store
        var proposed = output("Money arrives without a source.", time: .init(unit: .months, amount: 1), money: [
            .init(sourceType: .loan, amountMinor: 5_000_000, reason: "Unapproved loan", accountId: "personal")])
        proposed.resolution.accountOpenings = [.init(id: "business", name: "Business", kind: .business)]
        let wire = try envelope(proposed)
        let provider = provider([wire, wire])
        await #expect(throws: TurnError.self) {
            _ = try await TurnProcessor(store: store, narrator: LLMNarrator(provider: provider), fate: FixedFate([50])).play("Borrow money.")
        }
        #expect(provider.requests.count == 2)
        #expect(try store.revision() == 0 && store.character().currentDate == TestChat.date)
        #expect(try store.balanceMinor() == 175_000 && store.accounts().count == 1)
        #expect(try store.positions().isEmpty && store.recentMessages(limit: 20).isEmpty)
    }

    @Test func malformedPayloadRepairCountsBothResponsesAndCommitsOnce() async throws {
        let store = try TestChat.chat(TestChat.library()).store
        let base = provider([try envelope(resolution: "{"), try envelope(output("You look around."))])
        let tracker = try UsageTracker(url: FileManager.default.temporaryDirectory.appendingPathComponent("envelope-usage-\(UUID()).json"))
        let metered = MeteredProvider(base: base, tracker: tracker, providerName: "test", model: "fixture",
            inputUSDPerMillion: 1, outputUSDPerMillion: 1, dailyLimit: 1)
        let result = try await TurnProcessor(store: store, narrator: LLMNarrator(provider: metered), fate: FixedFate([50])).play("I look around.")
        #expect(result.repaired && base.requests.count == 2)
        #expect(try store.turnLogs().count == 1 && store.recentMessages(limit: 20).count == 2 && store.revision() == 1)
        let usage = await tracker.history()
        #expect(usage.count == 2 && usage.reduce(0) { $0 + $1.outputTokens } == 1_000)
    }
}
