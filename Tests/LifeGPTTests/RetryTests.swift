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

@Suite(.serialized) @MainActor struct AppModelFixTests {
    @Test func tolerantSettingsAndIndependentStartup() throws {
        for (name, body) in [("partial", "{\"provider\":\"anthropic\"}"), ("corrupt", "{")] {
            let r = try rig(); defer { try? FileManager.default.removeItem(at: r.paths.root) }
            try Data(body.utf8).write(to: r.paths.settings)
            try Data("garbage".utf8).write(to: r.paths.usage)
            let model = AppModel(paths: r.paths)
            #expect(model.lives.count == 1 && model.selection != nil && model.snapshot != nil, "\(name)")
            #expect(model.error != nil, "\(name)")
            if name == "partial" { #expect(model.settings.provider == .anthropic && model.settings.cloudTwoStep == false) }
        }
    }

    @Test func savingWithoutKeyKeepsStoredKeyAndWritesSettingsFirst() throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.paths.root) }
        KeychainStore.items = ["anthropic": "sk-old"]; defer { KeychainStore.items = [:]; KeychainStore.failReads = false }
        var s = AppSettings(); s.provider = .anthropic
        try r.model.saveSettings(s, key: nil)
        #expect(KeychainStore.items["anthropic"] == "sk-old")
        // A failing settings write must not touch the Keychain.
        try FileManager.default.removeItem(at: r.paths.settings)
        try FileManager.default.createDirectory(at: r.paths.settings, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try r.model.saveSettings(s, key: "sk-new") }
        #expect(KeychainStore.items["anthropic"] == "sk-old")
    }

    @Test func connectionTestKeyIsTrimmed() throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.paths.root) }
        var s = AppSettings(); s.provider = .anthropic; s.inputUSDPerMillion = 4; s.outputUSDPerMillion = 20
        let metered = try #require(try r.model.provider(using: s, keyOverride: "  sk-test\n") as? MeteredProvider)
        let key = Mirror(reflecting: metered.base).children.first { $0.label == "apiKey" }?.value as? String
        #expect(key == "sk-test")
    }

    @Test func providerFailuresAreRetryableAndKeepSkip() async throws {
        let r = try rig(narrator: ThrowingNarrator(error: ProviderError.http(status: 503, body: "")))
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let skip = TimeAdvance(unit: .months, amount: 2)
        r.model.composer = "I let two months pass."; r.model.send(skipTime: skip)
        await r.model.turnTask?.value
        #expect(r.model.canRetry && r.model.failedTurn?.skipTime == skip)
        // Pressing Send on the refilled composer keeps the skip.
        r.model.send()
        await r.model.turnTask?.value
        #expect(r.model.failedTurn?.skipTime == skip)
        #expect(await r.narrator.requestedTimes == [skip, skip])
    }

    @Test func urlErrorCancelledIsACancellationAndKeepsSkip() async throws {
        let r = try rig(narrator: ThrowingNarrator(error: URLError(.cancelled)))
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let skip = TimeAdvance(unit: .years, amount: 3)
        r.model.composer = "I let 3 years pass."; r.model.send(skipTime: skip)
        await r.model.turnTask?.value
        #expect(r.model.error == nil && r.model.information?.contains("cancelled") == true)
        #expect(r.model.failedTurn?.skipTime == skip && r.model.composer == "I let 3 years pass.")
    }

    @Test func updateWorldThrowsInsteadOfSilentNoOp() throws {
        let model = AppModel(paths: try AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("lifegpt-fix-\(UUID().uuidString)")))
        defer { try? FileManager.default.removeItem(at: model.paths!.root) }
        #expect(throws: (any Error).self) { try model.updateWorld(text: "t", location: "l", economy: .sampleUS2005) }
    }

    @Test func suggestionKeepsTypedDraft() async throws {
        let r = try rig(narrator: ThrowingNarrator(error: ProviderError.http(status: 500, body: "")))
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        r.model.composer = "my long draft"
        r.model.send("Take the job")
        #expect(r.model.composer == "my long draft")
        await r.model.turnTask?.value
        #expect(r.model.composer == "my long draft")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/chattr"))) func failedDeleteLeavesOpenLifeUntouched() throws {
        let r = try rig()
        let id = try #require(r.model.selection)
        let file = r.paths.chats.appendingPathComponent("\(id.uuidString).lifechat")
        @discardableResult func chattr(_ flag: String) -> Bool { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/chattr"); p.arguments = [flag, file.path]; guard (try? p.run()) != nil else { return false }; p.waitUntilExit(); return p.terminationStatus == 0 }
        guard chattr("+i") else { try? FileManager.default.removeItem(at: r.paths.root); return }  // immutable flag unsupported here (needs root + capable fs)
        defer { chattr("-i"); try? FileManager.default.removeItem(at: r.paths.root) }
        r.model.deleteLife(id)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(r.model.selection == id && r.model.snapshot != nil && r.model.error != nil)
    }

    @Test func worldReviewUsesElapsedYears() throws {
        let r = try rig(); defer { try? FileManager.default.removeItem(at: r.paths.root) }
        var snap = try #require(r.model.snapshot)
        let loc = snap.state["residence"] ?? "Anywhere"
        snap.state["residence"] = loc
        func check(_ brief: GameDate, _ now: GameDate) -> Bool {
            snap.world = [PlaceTimeBrief(date: brief, location: loc, text: "x")]; snap.character.currentDate = now
            return snap.worldNeedsReview
        }
        #expect(!check(GameDate(year: 2019, month: 12, day: 31), GameDate(year: 2020, month: 1, day: 5)))
        #expect(!check(GameDate(year: 2000, month: 1, day: 1), GameDate(year: 2019, month: 12, day: 31)))
        #expect(check(GameDate(year: 2000, month: 1, day: 1), GameDate(year: 2020, month: 1, day: 1)))
    }

    private func rig(narrator: ThrowingNarrator? = nil) throws -> (model: AppModel, narrator: ThrowingNarrator, paths: AppPaths) {
        let paths = try AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("lifegpt-fix-\(UUID().uuidString)"))
        let library = try ChatLibrary(directory: paths.chats)
        _ = try library.createChat(character: NewCharacter(name: "Richard", birthplace: "Texas, USA", birthYear: 1985, appearance: "Tall",
            startingAge: 18, background: nil, familyWealthTier: .wealthy), economy: .sampleUS2005)
        let n = narrator ?? ThrowingNarrator(error: CancellationError())
        return (AppModel(paths: paths, narratorFactory: { n }), n, paths)
    }
}

private actor ThrowingNarrator: Narrator {
    let error: any Error
    private(set) var requestedTimes: [TimeAdvance?] = []
    init(error: any Error) { self.error = error }
    func narrate(_ request: NarratorRequest) async throws -> NarratorResult { requestedTimes.append(request.requestedTime); throw error }
    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult { try await narrate(request) }
}
