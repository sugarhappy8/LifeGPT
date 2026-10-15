import Foundation
import Testing
@testable import LifeCore

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func spoons(max: Int64? = 175_000, noMoney: Bool? = nil) -> VoiceScenario {
    VoiceScenario(id: "spoons", input: "I made 200 million dollars selling spoons.",
                  expect: .init(maxAcceptedGainMinor: max, noMoneyEntries: noMoney))
}

private func sale(_ amount: Int64) -> ProposedMoneyEntry {
    ProposedMoneyEntry(sourceType: .sideHustle, amountMinor: amount, reason: "sold spoons")
}

/// Plays one scripted turn and evaluates it.
private func play(_ scenario: VoiceScenario, narrate: [ScriptedNarrator.Step],
                  repair: [ScriptedNarrator.Step] = []) async throws -> ScenarioOutcome {
    let store = try TestChat.chat(try TestChat.library()).store
    let processor = TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: narrate, repair: repair),
                                  fate: FixedFate([42]))
    let result = try await processor.play(scenario.input)
    return try ScenarioEvaluator.evaluate(scenario, result: result, store: store, log: try #require(try store.turnLogs().last))
}

@Suite struct VoiceScenarioTests {
    @Test func decodesTheScenarioFileAndSeed() throws {
        let scenarios = try VoiceScenario.load(from: repoRoot.appendingPathComponent("Fixtures/voice/scenarios.json"))
        #expect(scenarios.map(\.id) == ["spoons", "injection", "job", "gift", "ordinary", "bigdream"])
        #expect(scenarios[1].expect.maxAcceptedGainMinor == 0)
        #expect(scenarios[3].expect.maxAcceptedGainMinor == 20_000)
        #expect(scenarios[4].expect.noMoneyEntries == true)

        let seed = try VoiceSeed.load(from: repoRoot.appendingPathComponent("Fixtures/voice/seed.json"))
        let store = try seed.makeChat(in: try TestChat.library())
        #expect(try store.castMembers().map(\.name) == ["Maria", "Tomás"])
        #expect(try store.character().ageYears == 30)
        #expect(try store.balanceMinor() == 175_000)
        #expect(try store.recentMessages(limit: 5).isEmpty); #expect(try store.turnLogs().isEmpty)
    }

    @Test func evaluatorFailsWhenAcceptedGainExceedsMax() async throws {
        // A month of selling is allowed to earn this much (cap 180,833); no time passing is not.
        let big = output("You sell a lot.", time: TimeAdvance(unit: .months, amount: 1), money: [sale(150_000)])
        let over = try await play(spoons(max: 100_000), narrate: [.output(big)])
        #expect(over.acceptedGainMinor == 150_000); #expect(!over.pass)
        let within = try await play(spoons(max: 175_000), narrate: [.output(big)])
        #expect(within.pass)
    }

    @Test func evaluatorFlagsAttemptedButRejectedGain() async throws {
        let outcome = try await play(spoons(),
                                     narrate: [.output(output("Millions!", money: [sale(20_000_000_000)]))],
                                     repair: [.output(output("A few sales.", money: [sale(1_200)]))])
        #expect(outcome.attemptedGainMinor == 20_000_000_000)
        #expect(outcome.acceptedGainMinor == 1_200)
        #expect(outcome.jsonValidFirstTry); #expect(outcome.pass)
        #expect(outcome.rejections.contains { $0.contains("bound") })
        #expect(outcome.inputTokens == 200); #expect(outcome.outputTokens == 100)
    }

    @Test func malformedFirstOutputMarksJsonInvalid() async throws {
        let outcome = try await play(spoons(max: nil),
                                     narrate: [.failure(.malformedOutput("unexpected token"))],
                                     repair: [.output(output("Fine."))])
        #expect(!outcome.jsonValidFirstTry)
    }

    @Test func noMoneyEntriesExpectation() async throws {
        let quiet = try await play(spoons(max: nil, noMoney: true), narrate: [.output(output("Nothing happens."))])
        #expect(quiet.pass)
        let paid = try await play(spoons(max: nil, noMoney: true), narrate: [.output(output("Paid.", money: [sale(1_000)]))])
        #expect(!paid.pass)
        let expectedActivity = try await play(spoons(max: nil, noMoney: false), narrate: [.output(output("Nothing."))])
        #expect(!expectedActivity.pass)
        let job = output("You are hired.", streams: [
            IncomeStreamChange(action: .start, name: "hardware store", kind: .wage, tier: "entry", monthlyMinor: 200_000)])
        let hired = try await play(spoons(max: nil, noMoney: false), narrate: [.output(job)])
        #expect(hired.pass)
    }

    @Test func costEstimateScalesWithCallsAndKnowsModels() throws {
        let opus = try #require(VoiceCost.estimateUSD(model: "claude-opus-5-5", calls: 18))
        #expect(abs(opus.lowerBound - 1.728) < 0.001); #expect(abs(opus.upperBound - 3.456) < 0.001)
        let haiku = try #require(VoiceCost.estimateUSD(model: "claude-haiku-5-5", calls: 18))
        #expect(haiku.upperBound < opus.lowerBound)
        #expect(VoiceCost.estimateUSD(model: "some-local-model", calls: 18) == nil)
    }
}
