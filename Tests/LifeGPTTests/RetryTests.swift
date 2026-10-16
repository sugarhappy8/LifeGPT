import Foundation
import Testing
import LifeCore
@testable import LifeGPT

@Suite @MainActor struct RetryTests {
    @Test(arguments: [false, true])
    func retryPreservesActionDurationAndLengthWithoutDuplicateCommits(_ skip: Bool) async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let initialRevision = try r.store.revision()
        let initialDate = try r.store.character().currentDate
        let duration = skip ? TimeAdvance(unit: .months, amount: 1) : nil
        r.model.quickLength = skip ? 500 : 0
        let expectedWords = skip ? 500 : 200
        let text = skip ? "I let one month pass." : "I open my university letters."
        r.model.composer = text
        r.model.send(skipTime: duration)
        await r.model.turnTask?.value
        #expect(r.model.error == "The reply couldn’t be validated. Your life was not changed.")
        #expect(r.model.canRetry && r.model.composer == text)
        #expect(!r.model.validationDetails.isEmpty)
        #expect(r.model.pendingText == nil && !r.model.busy)
        #expect(try r.store.revision() == initialRevision)
        #expect(try r.store.messageCount() == 0)

        r.model.quickLength = 1000 // Retry uses the original choice, not a later picker value.
        r.model.retryTurn()
        await r.model.turnTask?.value
        let requests = await r.narrator.requests
        #expect(requests.count == 3) // One initial response, one repair, one manual retry.
        #expect(requests.allSatisfy { $0.playerInput == text && $0.requestedTime == duration && $0.targetWords == expectedWords })
        #expect(r.model.error == nil && r.model.failedTurn == nil && r.model.validationDetails.isEmpty)
        #expect(!r.model.canRetry && r.model.composer.isEmpty && r.model.quickLength == 0)
        #expect(try r.store.revision() == initialRevision + 1)
        #expect(try r.store.messageCount() == 2)
        #expect(try r.store.turnLogs().count == 1)
        #expect(try r.store.character().currentDate == (skip ? initialDate.adding(months: 1) : initialDate))
    }

    @Test func editingOrSwitchingLivesClearsRetry() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        r.model.composer = "I open a letter."; r.model.send()
        await r.model.turnTask?.value
        #expect(r.model.canRetry)
        r.model.composer += " Then I talk to my father."
        #expect(r.model.failedTurn == nil && !r.model.canRetry)
        r.model.retryTurn()
        #expect(await r.narrator.requests.count == 2)

        let second = try rig()
        defer { try? FileManager.default.removeItem(at: second.paths.root) }
        second.model.composer = "I look around."; second.model.send()
        await second.model.turnTask?.value
        let library = try ChatLibrary(directory: second.paths.chats)
        let other = try library.createChat(character: character(name: "Another life"), economy: .sampleUS2005)
        second.model.openLife(other.id)
        #expect(second.model.failedTurn == nil && !second.model.canRetry && second.model.composer.isEmpty)
        second.model.retryTurn()
        #expect(await second.narrator.requests.count == 2)
        #expect(try other.store.messageCount() == 0)
    }

    @Test func retryChecksExternalSaveChangesBeforeCallingTheNarrator() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        r.model.composer = "I open a letter."; r.model.send()
        await r.model.turnTask?.value
        try r.store.updateSettings(SessionSettings(), swingDial: 1, replyLengthWords: 500)
        let revision = try r.store.revision()
        r.model.retryTurn()
        #expect(r.model.failedTurn == nil && !r.model.canRetry)
        #expect(r.model.error?.contains("This life changed") == true)
        #expect(r.model.composer == "I open a letter.")
        #expect(await r.narrator.requests.count == 2)
        #expect(try r.store.revision() == revision && r.store.messageCount() == 0)
    }

    @Test func settingsEditsInvalidateRetryDuringRefresh() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        r.model.composer = "I open a letter."; r.model.send()
        await r.model.turnTask?.value
        try r.model.saveStorySettings(SessionSettings(), swing: 2, words: 200)
        #expect(!r.model.canRetry && r.model.failedTurn == nil)
        #expect(r.model.composer == "I open a letter.")
    }

    @Test func dismissingFailureDoesNotSaveAnything() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        r.model.composer = "I open a letter."; r.model.send()
        await r.model.turnTask?.value
        r.model.dismissError()
        #expect(r.model.error == nil && r.model.failedTurn == nil && r.model.validationDetails.isEmpty)
        #expect(r.model.composer == "I open a letter.")
        #expect(try r.store.messageCount() == 0)
    }

    @Test func householdAndDifficultyPersistAcrossReopeningAndInvalidateRetry() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        r.model.composer = "I open a letter."; r.model.send()
        await r.model.turnTask?.value
        #expect(r.model.canRetry)
        var settings = SessionSettings()
        settings.household = .familySupported; settings.difficulty = 10; settings.voiceBible = "Quiet scenes"
        try r.model.saveStorySettings(settings, swing: 1, words: 200)
        #expect(!r.model.canRetry && r.model.composer == "I open a letter.")
        #expect(r.model.snapshot?.personalLivingCost == 0)
        let reopened = AppModel(paths: r.paths)
        #expect(reopened.snapshot?.settings == settings)
        #expect(reopened.snapshot?.household == .familySupported && reopened.snapshot?.personalLivingCost == 0)
        #expect(try r.store.messageCount() == 0)
    }

    private func character(name: String = "Richard") -> NewCharacter {
        NewCharacter(name: name, birthplace: "Texas, USA", birthYear: 1985, appearance: "Tall", startingAge: 18,
            background: nil, familyWealthTier: .wealthy)
    }
    private func rig() throws -> (model: AppModel, store: LifeStore, narrator: RetryNarrator, paths: AppPaths) {
        let paths = try AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("lifegpt-retry-\(UUID().uuidString)"))
        let library = try ChatLibrary(directory: paths.chats)
        let store = try library.createChat(character: character(), economy: .sampleUS2005).store
        let narrator = RetryNarrator()
        let model = AppModel(paths: paths, narratorFactory: { narrator })
        return (model, store, narrator, paths)
    }
}

private actor RetryNarrator: Narrator {
    private(set) var requests: [NarratorRequest] = []
    func narrate(_ request: NarratorRequest) async throws -> NarratorResult {
        requests.append(request)
        var resolution = Resolution(zoom: .scene, timeAdvance: request.requestedTime ?? TimeAdvance(unit: .days, amount: 0))
        if requests.count <= 2 { resolution.crimeAttempt = CrimeAttempt(reason: String(repeating: "x", count: 501)) }
        return NarratorResult(output: TurnOutput(resolution: resolution, narration: "A quiet scene continues."), inputTokens: 10, outputTokens: 20)
    }
    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult { try await narrate(request) }
}
