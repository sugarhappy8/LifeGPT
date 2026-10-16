import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import LifeCore

@MainActor @Observable
final class AppModel {
    var settings = AppSettings()
    var lives: [ChatSummary] = []
    var selection: UUID?
    var snapshot: LifeSnapshot?
    var showNewLife = false
    var showInspector = true
    var inspectorTab = InspectorTab.life
    var showStorySettings = false
    var showWorldEditor = false
    var showFinanceManager = false
    var showBusinessManager = false
    var showRoleplayGuide = false
    var error: String?
    var information: String?
    var libraryWarnings: [String] = []
    var composer = "" {
        didSet {
            if let failedTurn, composer != failedTurn.text { clearFailedTurn() }
        }
    }
    var pendingText: String?
    var busy = false
    var quickLength = 0
    var search = ""
    var deleteCandidate: UUID?
    var usage: [UsageRecord] = []
    var messageLimit = 100
    private(set) var paths: AppPaths?
    private var library: ChatLibrary?
    private var store: LifeStore?
    private var tracker: UsageTracker?
    private(set) var turnTask: Task<Void, Never>?
    private(set) var failedTurn: TurnAttempt?
    private(set) var validationDetails: [String] = []
    @ObservationIgnored private let narratorFactory: (() throws -> any Narrator)?

    init(paths suppliedPaths: AppPaths? = nil, narratorFactory: (() throws -> any Narrator)? = nil) {
        self.narratorFactory = narratorFactory
        do {
            let paths = try suppliedPaths ?? AppPaths(); self.paths = paths
            library = try ChatLibrary(directory: paths.chats)
            tracker = try UsageTracker(url: paths.usage)
            if FileManager.default.fileExists(atPath: paths.settings.path) {
                settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: paths.settings))
            }
            try refreshLibrary()
            if let id = lives.first?.id { openLife(id) }
        } catch { self.error = error.localizedDescription }
    }
    var filteredLives: [ChatSummary] {
        search.isEmpty ? lives : lives.filter { $0.characterName.localizedCaseInsensitiveContains(search) }
    }
    var todayCost: Double { usage.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.estimatedUSD } }
    var providerLabel: String { settings.provider.title }
    var canSend: Bool { !busy && snapshot != nil && snapshot?.ended == false && !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canRetry: Bool { !busy && failedTurn != nil && failedTurn?.lifeID == selection && snapshot?.ended == false }

    func refreshLibrary() throws {
        lives = try library?.list() ?? []
        libraryWarnings = try library?.unreadableFiles() ?? []
    }
    func openLife(_ id: UUID) {
        guard !busy else { return }
        do {
            guard let library else { throw ValidationError.invalid("The save library is unavailable.") }
            let next = try library.openChat(id: id)
            let nextSnapshot = try LifeSnapshot(store: next)
            store = next; snapshot = nextSnapshot; selection = id; messageLimit = 100
            clearFailedTurn()
            composer = ""; information = nil; error = nil; quickLength = 0
        } catch { self.error = error.localizedDescription }
    }
    func reload() throws {
        if let store {
            snapshot = try LifeSnapshot(store: store, messageLimit: messageLimit)
            if let failedTurn, try store.revision() != failedTurn.revision { clearFailedTurn() }
        }
        try refreshLibrary()
    }
    func updateFinances(accountOpenings: [AccountOpening], streamChanges: [IncomeStreamChange],
                        transfers: [AccountTransfer], expectedLifeID: UUID, expectedRevision: Int) throws {
        guard !busy, let store else { throw ValidationError.invalid("Wait for the current turn before editing finances.") }
        guard try store.character().id == expectedLifeID else {
            throw ValidationError.invalid("A different life is open. Reopen Manage finances before editing.")
        }
        guard try store.revision() == expectedRevision else {
            try reload()
            throw ValidationError.invalid("This life changed. Reopen Manage finances to use its current records.")
        }
        try BankingEngine.manage(store: store, openings: accountOpenings, changes: streamChanges,
            transfers: transfers, expectedRevision: expectedRevision)
        try reload()
    }
    func updateBusinesses(businessChanges: [BusinessChange] = [], obligations: [ObligationChange] = [],
                          accounts: [AccountLifecycleChange] = [], sales: [SaleProposal] = [], convertLegacy: Bool = false,
                          expectedLifeID: UUID, expectedRevision: Int) throws {
        guard !busy, let store, try store.character().id == expectedLifeID else { throw ValidationError.invalid("Reopen finances for the active life after the current turn finishes.") }
        try store.updateBusinessSimulation(businessChanges: businessChanges, obligationChanges: obligations,
            accountChanges: accounts, saleProposals: sales, convertLegacyIncome: convertLegacy, expectedRevision: expectedRevision)
        try reload()
    }
    func updateFiscalProfile(jurisdiction: JurisdictionRef, values: FiscalOverrides, lifeID: UUID, revision: Int) throws {
        guard !busy, let store, try store.character().id == lifeID else { throw ValidationError.invalid("Reopen tax settings for the active life.") }
        try store.updateFiscalOverride(jurisdiction: jurisdiction, values: values, expectedRevision: revision); try reload()
    }
    func confirmSale(_ id: String, lifeID: UUID, revision: Int) throws {
        guard !busy, let store, try store.character().id == lifeID else { throw ValidationError.invalid("Open the sale's life before confirming.") }
        try store.confirmBusinessSale(id: id, expectedRevision: revision); try reload()
    }
    func loadEarlier() {
        messageLimit += 100
        do { try reload() } catch { self.error = error.localizedDescription }
    }
    func saveSettings(_ new: AppSettings, key: String?) throws {
        try new.validate()
        guard let paths else { throw ValidationError.invalid("The settings folder is unavailable.") }
        if let key, new.usesCloud { try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: new.provider.rawValue) }
        try JSONEncoder().encode(new).write(to: paths.settings, options: .atomic)
        settings = new
    }
    func provider(using config: AppSettings? = nil, keyOverride: String? = nil) throws -> any AIProvider {
        let config = config ?? settings
        try config.validate()
        let transport = ResilientTransport()
        let base: any AIProvider
        switch config.provider {
        case .demo: throw ValidationError.invalid("The offline demo uses built-in scenes and manual setup. Choose a model to generate a world.")
        case .local:
            guard let url = URL(string: config.localServer) else { throw ValidationError.invalid("The local server URL is invalid.") }
            return try LocalProvider(baseURL: url, model: config.localModel, contextTokens: config.contextTokens,
                structuredOutput: config.localStructuredOutput, transport: transport)
        case .anthropic, .gemini:
            let key = try keyOverride ?? KeychainStore.read(config.provider.rawValue)
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.invalid("Add your \(config.provider.title) API key in Settings first.") }
            if config.provider == .anthropic {
                base = AnthropicProvider(apiKey: key, model: config.anthropicModel, useRefusalFallback: false, transport: transport)
            } else { base = GeminiProvider(apiKey: key, model: config.geminiModel, contextTokens: 128_000, transport: transport) }
        }
        guard let tracker else { throw ValidationError.invalid("Usage tracking is unavailable; restore the usage file before making paid calls.") }
        return MeteredProvider(base: base, tracker: tracker, providerName: config.provider.rawValue, model: config.model,
            inputUSDPerMillion: config.inputUSDPerMillion, outputUSDPerMillion: config.outputUSDPerMillion, dailyLimit: config.dailyLimitUSD)
    }
    func refreshUsage() async { if let tracker { usage = await tracker.history() } }
    func testConnection(config: AppSettings, key: String) async throws -> String {
        if config.provider == .demo { return "The offline demo is ready. No network connection is needed." }
        let provider = try provider(using: config, keyOverride: key)
        let response = try await provider.complete(ProviderRequest(system: "Reply with exactly OK.", user: "Connection test.", maxOutputTokens: 128, jsonSchema: nil))
        await refreshUsage()
        guard !response.text.isEmpty, response.stopReason != .refusal else { throw ProviderError.badResponse }
        return "Connected to \(config.model). The server returned a response."
    }
    func generateSetup(_ character: NewCharacter) async throws -> SetupDraft {
        let generator = try SetupGenerator(provider: provider())
        do { let draft = try await generator.generate(character); await refreshUsage(); return draft }
        catch { await refreshUsage(); throw error }
    }
    func generateWorld(location: String, jurisdiction: JurisdictionRef? = nil) async throws -> WorldDraft {
        guard let snapshot else { throw ValidationError.invalid("Open a life first.") }
        let generator = try WorldGenerator(provider: provider())
        do {
            let draft = try await generator.generate(location: location, character: snapshot.character, economy: snapshot.economy, jurisdiction: jurisdiction)
            await refreshUsage(); return draft
        } catch { await refreshUsage(); throw error }
    }
    func createLife(character: NewCharacter, setup: SetupDraft, storySettings: SessionSettings) throws {
        guard let library else { throw ValidationError.invalid("The save library is unavailable.") }
        let created = try library.createChat(character: character, setup: setup, settings: storySettings)
        try refreshLibrary(); openLife(created.id); showNewLife = false
    }
    func send(_ suggestion: String? = nil, skipTime: TimeAdvance? = nil) {
        guard !busy, let store, let selection, let snapshot, !snapshot.ended else { return }
        let text = (suggestion ?? composer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        clearFailedTurn()
        if case .outOfCharacter(let question) = IntentGuard.classify(text) {
            do {
                if ["longer", "shorter"].contains(question.lowercased()) {
                    let current = snapshot.character.replyLengthWords
                    let length = question.lowercased() == "longer" ? min(2000, current * 2) : max(60, current / 2)
                    try store.updateSettings(snapshot.settings, swingDial: snapshot.character.swingDial, replyLengthWords: length)
                    information = "Reply length is now about \(length) words."
                    try reload()
                } else { information = try OOCResponder.answer(question, store: store) }
                composer = ""
            } catch { self.error = error.localizedDescription }
            return
        }
        do {
            let attempt = TurnAttempt(lifeID: selection, revision: try store.revision(), text: text,
                skipTime: skipTime, targetWords: quickLength > 0 ? quickLength : snapshot.character.replyLengthWords,
                lengthChoice: quickLength)
            submit(attempt)
        } catch { self.error = error.localizedDescription }
    }

    func retryTurn() {
        guard canRetry, let attempt = failedTurn else { return }
        submit(attempt)
    }

    func dismissError() { error = nil; clearFailedTurn() }

    private func clearFailedTurn() { failedTurn = nil; validationDetails = [] }

    private func submit(_ attempt: TurnAttempt) {
        guard !busy, let store, selection == attempt.lifeID, snapshot?.ended == false else { return }
        let narrator: any Narrator
        do {
            guard try store.revision() == attempt.revision else {
                clearFailedTurn()
                try reload()
                error = "This life changed since the failed reply. Review the current story before sending your action again."
                return
            }
            if let narratorFactory { narrator = try narratorFactory() }
            else if settings.provider == .demo { narrator = DemoNarrator() }
            else {
                let twoStep = settings.provider == .local ? settings.localTwoStep : settings.cloudTwoStep
                narrator = try LLMNarrator(provider: provider(), mode: twoStep ? .twoStep : .singleCall)
            }
        } catch { self.error = error.localizedDescription; return }
        let processor = TurnProcessor(store: store, narrator: narrator, fate: SeededFate(seed: UInt64.random(in: .min ... .max)))
        clearFailedTurn()
        busy = true; pendingText = attempt.text; composer = ""; error = nil; information = nil
        quickLength = attempt.lengthChoice
        turnTask = Task {
            defer { busy = false; pendingText = nil; turnTask = nil }
            do {
                let result = try await processor.play(attempt.text, targetWords: attempt.targetWords, skipTime: attempt.skipTime)
                if !result.contextNotice.isEmpty { information = result.contextNotice }
            } catch is CancellationError {
                composer = attempt.text; information = "The reply was cancelled. Your life was not changed."
                await refreshUsage()
                return
            } catch {
                composer = attempt.text
                self.error = error.localizedDescription
                if let turnError = error as? TurnError {
                    switch turnError {
                    case .validationFailed(let reasons): validationDetails = reasons
                    case .narratorFailed: break
                    case .refused: await refreshUsage(); return
                    }
                    // A stale save is never replayed, even if an external writer changed it mid-request.
                    if (try? store.revision()) == attempt.revision { failedTurn = attempt }
                }
                await refreshUsage()
                return
            }
            // A refresh failure after commit must not offer a retry of an already-saved action.
            clearFailedTurn(); quickLength = 0
            do { try reload() }
            catch { self.error = "Your turn was saved, but the view could not refresh. Reopen this life. \(error.localizedDescription)" }
            await refreshUsage()
        }
    }
    func cancelTurn() { turnTask?.cancel() }
    func saveStorySettings(_ settings: SessionSettings, swing: Int, words: Int) throws {
        guard !busy else { throw ValidationError.invalid("Wait for the current turn to finish.") }
        try store?.updateSettings(settings, swingDial: swing, replyLengthWords: words); try reload()
    }
    func updateWorld(text: String, location: String, economy: EconomyCard, jurisdiction: JurisdictionRef? = nil, lifeID: UUID? = nil, revision: Int? = nil) throws {
        guard !busy, let store, let snapshot else { return }
        guard lifeID == nil || snapshot.character.id == lifeID else { throw ValidationError.invalid("Reopen the world editor for the current life.") }
        try store.saveWorld(brief: PlaceTimeBrief(date: snapshot.character.currentDate, location: location, text: text), economy: economy,
            jurisdiction: jurisdiction, expectedRevision: revision)
        try reload()
    }
    func deleteLife(_ id: UUID) {
        guard !busy else { return }
        do {
            if selection == id { clearFailedTurn(); store = nil; snapshot = nil; selection = nil }
            try library?.deleteChat(id: id); try refreshLibrary()
            if selection == nil, let next = lives.first?.id { openLife(next) }
        } catch { self.error = error.localizedDescription }
        deleteCandidate = nil
    }
    func revealSaves() { if let paths { NSWorkspace.shared.open(paths.chats) } }
    func importLife() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lifechat") ?? .data]
        panel.message = "Import a LifeGPT save as a separate life."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let library else { return }
            let id = try library.importChat(from: url); try refreshLibrary(); openLife(id)
        } catch { self.error = error.localizedDescription }
    }
    func exportBackup() {
        guard let store, let snapshot, !busy else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = safeFilename(snapshot.character.name) + ".lifechat"
        panel.allowedContentTypes = [UTType(filenameExtension: "lifechat") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Stage the SQLite backup before atomically replacing a user-approved destination.
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".lifegpt-export-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try store.backup(to: temporary)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: url) }
            information = "Save exported."
        } catch { self.error = error.localizedDescription }
    }
    func exportStory() {
        guard let store, let snapshot else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = safeFilename(snapshot.character.name) + " — A Life.md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var text = "# \(snapshot.character.name)\n\nBorn \(snapshot.character.birthYear), \(snapshot.character.birthplace).\n\n"
            var after: Int64 = 0
            while true {
                let page = try store.messages(after: after, limit: 500)
                if page.isEmpty { break }
                for message in page { text += "\n## \(message.date.iso) · \(message.role == .player ? "You" : "Narrator")\n\n\(message.text)\n" }
                after = page.last!.id
            }
            try text.write(to: url, atomically: true, encoding: .utf8); information = "Story exported."
        } catch { self.error = error.localizedDescription }
    }
    private func safeFilename(_ text: String) -> String {
        text.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
    }
}

/// Only retained in memory after an unsuccessful model response; never written into a life.
struct TurnAttempt: Equatable {
    let lifeID: UUID
    let revision: Int
    let text: String
    let skipTime: TimeAdvance?
    let targetWords: Int
    let lengthChoice: Int
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case life = "Life", finances = "Finances", people = "People", decisions = "Decisions", timeline = "Timeline", paths = "Paths", memory = "Memory"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .life: "person.crop.rectangle"; case .finances: "banknote"; case .people: "person.2";
        case .decisions: "arrow.triangle.branch"; case .timeline: "clock"; case .paths: "point.topleft.down.to.point.bottomright.curvepath"; case .memory: "books.vertical" }
    }
}
