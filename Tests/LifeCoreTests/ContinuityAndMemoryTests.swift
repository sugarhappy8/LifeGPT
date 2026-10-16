import Foundation
import Testing
@testable import LifeCore

@Suite struct ContinuityAndMemoryTests {
    @Test func deadCastAndEngineFactsCannotBeOverridden() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try store.seedHistory(cast: [CastUpdate(name: "Nora", relation: "sister", notes: nil, status: "dead")], decisions: [], lifeState: [])
        let truth = try GroundTruthBuilder.build(store: store, rules: .v1)
        let resolution = Resolution(zoom: .scene, timeAdvance: TimeAdvance(unit: .days, amount: 0),
            lifeStateChanges: [LifeStateChange(key: "balance", value: "a million")],
            castUpdates: [CastUpdate(name: "Nora", relation: nil, notes: nil, status: "alive")])
        let verdict = ContinuityValidator.validate(resolution, truth: truth)
        #expect(verdict.cast.isEmpty); #expect(verdict.state.isEmpty); #expect(verdict.rejections.count == 2)
    }
    @Test func optionalUncannyReturnNeedsBothADialAndEvent() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try store.seedHistory(cast: [CastUpdate(name: "Nora", relation: nil, notes: nil, status: "dead")], decisions: [], lifeState: [])
        var truth = try GroundTruthBuilder.build(store: store, rules: .v1)
        truth.character.swingDial = 2
        var resolution = Resolution(zoom: .scene, timeAdvance: TimeAdvance(unit: .days, amount: 0),
            castUpdates: [CastUpdate(name: "Nora", relation: nil, notes: nil, status: "alive")])
        #expect(ContinuityValidator.validate(resolution, truth: truth).cast.isEmpty)
        resolution.events = [EventRecord(title: "An uncanny return", importance: .major, uncanny: true)]
        #expect(ContinuityValidator.validate(resolution, truth: truth).cast.count == 1)
    }
    @Test func engineStoresNotesChoicesAndStopsAtDeath() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        var ending = output("The life reaches its end.")
        ending.authorNotes = "Remember the garden."; ending.choices = []
        ending.resolution.lifeEnded = true
        let narrator = ScriptedNarrator(narrate: [.output(ending)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42]))
        _ = try await processor.play("I reflect on my life.")
        #expect(try store.authorNotes() == "Remember the garden.")
        #expect(try store.hasEnded())
        await #expect(throws: ValidationError.self) { _ = try await processor.play("I go outside.") }
        #expect(narrator.narrateCalls == 1)
        #expect(try await processor.play("((balance))").kind == .outOfCharacter)
    }
    @Test func explicitSkipTimeIsOwnedByTheEngine() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        let o = output("A month passes.")
        let repaired = output("A month passes.", time: TimeAdvance(unit: .months, amount: 1))
        let narrator = ScriptedNarrator(narrate: [.output(o)], repair: [.output(repaired)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42]))
        _ = try await processor.play("I wait.", skipTime: TimeAdvance(unit: .months, amount: 1))
        #expect(try store.character().currentDate == TestChat.date.adding(months: 1))
        #expect(narrator.lastRequest?.requestedTime?.amount == 1)
    }
    @Test func repeatedSameDaySideHustlesShareOneBudget() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        let sale = output("A modest sale.", money: [ProposedMoneyEntry(sourceType: .sideHustle, amountMinor: 30_000, reason: "Market sale")])
        let narrator = ScriptedNarrator(narrate: [.output(sale), .output(sale)], repair: [.output(sale)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42]))
        _ = try await processor.play("I sell something.")
        await #expect(throws: TurnError.self) { _ = try await processor.play("I sell something again.") }
        #expect(try store.balanceMinor() == 205_000)
    }
    @Test func currentPlayerInputAndFinancialTruthSurviveBudgeting() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        let input = "I meet Nora at the cafe."
        var request = NarratorRequest(groundTruth: try GroundTruthBuilder.build(store: store, rules: .v1), playerInput: input, fate: 42, targetWords: 200, recentMessages: [])
        request.memory.excerpts = Array(repeating: String(repeating: "History ", count: 500), count: 20)
        let bounded = try ContextBuilder.budget(request, contextTokens: 16_384, outputTokens: 2048, rejections: [])
        #expect(bounded.playerInput == input)
        #expect(bounded.groundTruth.balanceMinor == 175_000)
        #expect(bounded.memory.excerpts.count < 20)
        #expect(ContextBuilder.ranked(["A quiet afternoon", "Nora at the cafe"], matching: input).first == "Nora at the cafe")
    }
    @Test func childSafetyGateRunsBeforeNarration() async throws {
        let store = try TestChat.chat(try TestChat.library(), age: 12).store
        let narrator = ScriptedNarrator(narrate: [])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42]))
        await #expect(throws: ValidationError.self) { _ = try await processor.play("Write an erotic scene.") }
        #expect(narrator.narrateCalls == 0)
        #expect(try store.messageCount() == 0)
    }
    @Test func cancellationCannotCommitATurnEvenIfNarratorIgnoresIt() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        let processor = TurnProcessor(store: store, narrator: SlowNarrator(), fate: FixedFate([42]))
        let task = Task { try await processor.play("I wait.") }
        try await Task.sleep(for: .milliseconds(10)); task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch { }
        #expect(try store.messageCount() == 0)
        #expect(try store.balanceMinor() == 175_000)
    }
}

private struct SlowNarrator: Narrator {
    func narrate(_ request: NarratorRequest) async throws -> NarratorResult {
        try? await Task.sleep(for: .milliseconds(100))
        return NarratorResult(output: output("A quiet moment."), inputTokens: 0, outputTokens: 0)
    }
    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult { try await narrate(request) }
}

@Suite struct NormalizedContinuityTests {
    @Test func caseAndWhitespaceCannotBypassReservedFactsOrDeath() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try store.seedHistory(cast: [CastUpdate(name: "Nora", relation: nil, notes: nil, status: "DEAD")], decisions: [], lifeState: [])
        let truth = try GroundTruthBuilder.build(store: store, rules: .v1)
        let changes = Resolution(zoom: .scene, timeAdvance: TimeAdvance(unit: .days, amount: 0),
            lifeStateChanges: [LifeStateChange(key: " Balance ", value: "million"), LifeStateChange(key: " _ENGINE_last_crime_date ", value: "1900-01-01")],
            castUpdates: [CastUpdate(name: " Nora ", relation: nil, notes: nil, status: " Alive ")])
        let validated = ContinuityValidator.validate(changes, truth: truth)
        #expect(validated.cast.isEmpty)
        #expect(validated.state.isEmpty)
        #expect(validated.rejections.count == 3)
    }
}
