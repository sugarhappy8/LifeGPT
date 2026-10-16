import Foundation
import Testing
@testable import LifeCore

@Suite struct ContextSelectionTests {
    private let selectionJSON = #"{"record_ids":["message:old"],"categories":[]}"#
    private func request(_ input: String = "I review the business payroll.", mode: ContextLookupMode = .automatic) throws -> NarratorRequest {
        let store = try TestChat.chat(TestChat.library()).store
        var request = NarratorRequest(groundTruth: try GroundTruthBuilder.build(store: store, rules: .v1),
            playerInput: input, fate: 50, targetWords: 200, recentMessages: [])
        request.memory.settings.contextLookupMode = mode
        request.memory.records = [
            ContextRecord(id: "message:old", category: .message, date: .init(year: 2019, month: 5, day: 2), text: "The saved payroll agreement says Nora earns 200000 minor units monthly."),
            ContextRecord(id: "event:garden", category: .event, date: .init(year: 2018, month: 1, day: 3), text: "The garden gate was painted green.")]
        request.memory.excerpts = ["Locally matched history: the office opened last year."]
        return request
    }
    private func wire() throws -> String {
        String(decoding: try OutputCoding.encoder.encode(output("You review the records.")), as: UTF8.self)
    }

    @Test func settingsAreBackwardCompatibleAndPersistSelectionMode() throws {
        #expect(try JSONDecoder().decode(SessionSettings.self, from: Data("{}".utf8)).contextLookupMode == .automatic)
        var settings = SessionSettings(); settings.contextLookupMode = .off
        #expect(try JSONDecoder().decode(SessionSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test(arguments: ["I pay my employees.", "I sell my company.", "Remember the promise to Nora.", "Three months pass."])
    func automaticLookupRecognizesComplexActions(_ input: String) throws {
        #expect(ContextSelector.shouldLookup(try request(input)))
    }

    @Test func modesAndExplicitSkipControlLookup() throws {
        #expect(!ContextSelector.shouldLookup(try request("I watch the sunset.")))
        #expect(ContextSelector.shouldLookup(try request("I watch the sunset.", mode: .always)))
        #expect(!ContextSelector.shouldLookup(try request("Pay the salary.", mode: .off)))
        var skip = try request("I wait."); skip.requestedTime = .init(unit: .months, amount: 1)
        #expect(ContextSelector.shouldLookup(skip))
        skip.memory.records = []
        #expect(!ContextSelector.shouldLookup(skip))
    }

    @Test func selectionRetrievesOnlyWhitelistedDatedRecordsBeforeNarration() async throws {
        var request = try request()
        request.groundTruth.simulationContext = "Business vidshare; payroll 200000; jurisdiction US-TX; effective 2020-01-01."
        let provider = StubProvider(responses: [StubProvider.reply(selectionJSON), StubProvider.reply(try wire())])
        let result = try await LLMNarrator(provider: provider).narrate(request)
        #expect(provider.requests.count == 2)
        #expect(provider.requests[0].system.contains("read-only context selection"))
        #expect(provider.requests[0].user.contains("jurisdiction US-TX"))
        #expect(provider.requests[1].user.contains("[message:old] 2019-05-02 message:"))
        #expect(provider.requests[1].user.contains("Nora earns 200000"))
        #expect(!provider.requests[1].user.contains("garden gate"))
        #expect(result.inputTokens == 2_000 && result.outputTokens == 1_000)
    }

    @Test func lookupIsSeparateFromProseDraftingAndNeverRepeatsDuringRepair() async throws {
        let provider = StubProvider(responses: [StubProvider.reply(selectionJSON), StubProvider.reply("A draft."), StubProvider.reply(try wire()),
                                                StubProvider.reply("A corrected draft."), StubProvider.reply(try wire())])
        let narrator = LLMNarrator(provider: provider, mode: .twoStep)
        let request = try request()
        _ = try await narrator.narrate(request)
        _ = try await narrator.repair(request, rejections: ["Keep the original date."])
        #expect(provider.requests.count == 5)
        #expect(provider.requests.filter { $0.system.contains("read-only context selection") }.count == 1)
        #expect(provider.requests.filter { $0.system.contains("For this drafting stage only") }.count == 2)
        #expect(provider.requests[4].user.contains("[message:old] 2019-05-02 message:"))
    }

    @Test(arguments: ["not JSON", #"{"record_ids":["other-life:account", "../../secret"],"categories":["files"]}"#])
    func invalidSelectionsFallBackWithoutASecondLookup(_ text: String) async throws {
        let provider = StubProvider(responses: [StubProvider.reply(text), StubProvider.reply(try wire())])
        _ = try await LLMNarrator(provider: provider).narrate(try request())
        #expect(provider.requests.count == 2)
        #expect(provider.requests[1].user.contains("Locally matched history: the office opened last year."))
        #expect(provider.requests[1].user.contains("locally matched history was used"))
        #expect(!provider.requests[1].user.contains("../../secret"))
    }

    @Test func networkFailureFallsBackButCancellationStopsTheTurn() async throws {
        let failed = StubProvider(responses: [.failure(ProviderError.badResponse), StubProvider.reply(try wire())])
        _ = try await LLMNarrator(provider: failed).narrate(try request())
        #expect(failed.requests.count == 2)
        let cancelled = StubProvider(responses: [.failure(CancellationError()), StubProvider.reply(try wire())])
        await #expect(throws: CancellationError.self) {
            _ = try await LLMNarrator(provider: cancelled).narrate(request())
        }
        #expect(cancelled.requests.count == 1)
    }

    @Test func categorySelectionAndDuplicateIDsAreBounded() async throws {
        var request = try request()
        request.memory.records = (1...50).map {
            ContextRecord(id: "ledger:\($0)", category: .ledger, date: TestChat.date, text: "Payroll installment \($0).")
        }
        let provider = StubProvider(responses: [StubProvider.reply(#"{"record_ids":["ledger:1","ledger:1","foreign:1"],"categories":["ledger"]}"#)])
        let selected = try await ContextSelector.select(request, provider: provider)
        #expect(selected.request.memory.excerpts.count == 12)
        #expect(Set(selected.request.memory.excerpts).count == 12)
        #expect(!selected.request.memory.excerpts.joined().contains("foreign"))
    }

    @Test func offUsesNoLookupAndPlainProvidersReceiveTheSelectionContract() async throws {
        let off = StubProvider(responses: [StubProvider.reply(try wire())])
        _ = try await LLMNarrator(provider: off).narrate(try request(mode: .off))
        #expect(off.requests.count == 1)
        var capabilities = StubProvider.capable; capabilities.supportsJSONSchema = false
        let plain = StubProvider(capabilities: capabilities, responses: [StubProvider.reply(selectionJSON)])
        _ = try await ContextSelector.select(try request(), provider: plain)
        #expect(plain.requests[0].jsonSchema == nil)
        #expect(plain.requests[0].user.contains("Response JSON schema:"))
    }

    @Test func archivedFinancialCategoriesCanBeSelectedWithoutInventingAccess() async throws {
        var request = try request("Remember the old payroll agreement and sale.")
        request.memory.records = [
            .init(id: "obligation:old:0", category: .obligation, date: TestChat.date, text: "Past agreement: Nora earned 200000 until it ended."),
            .init(id: "sale:closed", category: .business, date: TestChat.date, text: "Confirmed sale. The account was transferred to Buyer."),
            .init(id: "assessment:jan", category: .assessment, date: TestChat.date, text: "January withholding was recorded under the saved rule version.")]
        let provider = StubProvider(responses: [StubProvider.reply(#"{"record_ids":[],"categories":["business","obligation","assessment"]}"#)])
        let selected = try await ContextSelector.select(request, provider: provider)
        #expect(selected.request.memory.excerpts.count == 3)
        #expect(selected.request.groundTruth == request.groundTruth)
        #expect(provider.requests[0].jsonSchema?.contains("\"assessment\"") == true)
    }

    @Test func activeCastAndCommitmentsSurviveTrimmingAndOversizedEssentialsFailBeforeAnyCall() async throws {
        let store = try TestChat.chat(TestChat.library()).store
        try store.seedHistory(cast: (0..<20).map { .init(name: "Person \($0)", relation: "friend", notes: "An active relationship.", status: "alive") }, decisions: [], lifeState: [])
        var request = try request()
        request.groundTruth = try GroundTruthBuilder.build(store: store, rules: .v1)
        request.memory.threads = [.init(id: "promise", title: "Promise to repay", notes: "A binding outstanding promise.")]
        request.memory.excerpts = Array(repeating: String(repeating: "Old history. ", count: 500), count: 30)
        let bounded = try ContextBuilder.budget(request, contextTokens: 32_768, outputTokens: 2048, rejections: [])
        #expect(bounded.groundTruth.cast.count == 20)
        #expect(bounded.memory.threads.count == 1)
        request.groundTruth.simulationContext = String(repeating: "Essential outstanding payroll and restricted business ownership. ", count: 5000)
        var capabilities = StubProvider.capable; capabilities.maxContextTokens = 32_768
        let provider = StubProvider(capabilities: capabilities, responses: [])
        await #expect(throws: ValidationError.self) { _ = try await LLMNarrator(provider: provider).narrate(request) }
        #expect(provider.requests.isEmpty)
    }

    @Test func completedLookupAndFailedMainReplyRemainInUsageAccounting() async throws {
        let provider = StubProvider(responses: [StubProvider.reply("malformed lookup"), StubProvider.reply("malformed main reply")])
        let usageURL = FileManager.default.temporaryDirectory.appendingPathComponent("lookup-usage-\(UUID()).json")
        let tracker = try UsageTracker(url: usageURL)
        let metered = MeteredProvider(base: provider, tracker: tracker, providerName: "test", model: "fixture",
            inputUSDPerMillion: 1, outputUSDPerMillion: 1, dailyLimit: 10)
        await #expect(throws: NarratorError.self) { _ = try await LLMNarrator(provider: metered).narrate(request()) }
        let history = await tracker.history()
        #expect(history.count == 2)
        #expect(history.reduce(0) { $0 + $1.inputTokens } == 2_000)
        let contextRequest = try #require(history.first { $0.purpose == "Context selection" })
        #expect(contextRequest.inputTokens == 1_000 && contextRequest.outputTokens == 500)
        #expect(abs(contextRequest.estimatedUSD - 0.0015) < 0.00000001)
        #expect(history.filter { $0.purpose == "Context selection" }.count == 1)
        let reopened = try UsageTracker(url: usageURL)
        #expect(await reopened.history().first { $0.id == contextRequest.id }?.purpose == "Context selection")
    }

    @Test func storeCollectionIsReadOnlyAndCannotIncludeAnotherLife() throws {
        let library = try TestChat.library()
        let first = try TestChat.chat(library, name: "First").store
        let second = try TestChat.chat(library, name: "Second").store
        try first.apply(TestChat.turn(events: [.init(title: "First life agreement", importance: .major, uncanny: false)]))
        try second.apply(TestChat.turn(events: [.init(title: "Second life secret", importance: .major, uncanny: false)]))
        for index in 0..<7 { try first.apply(TestChat.turn(playerText: "Earlier action \(index)", narration: "Earlier event \(index)")) }
        let revision = try first.revision()
        let memory = try ContextBuilder.memory(store: first, input: "Remember the agreement.")
        #expect(memory.records.contains { $0.category == .event && $0.text == "[major] First life agreement" })
        #expect(memory.records.contains { $0.category == .message })
        #expect(!memory.records.contains { $0.text.contains("Second life") })
        #expect(try first.revision() == revision)
        let recent = try first.recentMessages(limit: 12)
        let prompt = try PromptRenderer.render(NarratorRequest(groundTruth: GroundTruthBuilder.build(store: first, rules: .v1),
            playerInput: "Continue.", fate: 50, targetWords: 200, recentMessages: recent))
        #expect(prompt.user.contains("2020-01-01 Player (earlier attempt):"))
    }

    @Test func foreignEmployeeTaxResidenceProfilesStayBindingAndKeepAccruedRuleDates() async throws {
        let texas = JurisdictionRef(countryID: "US", subdivisionID: "US-TX")
        let japan = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13")
        var character = TestChat.newCharacter()
        character.birthJurisdiction = texas; character.startingJurisdiction = texas
        let store = try TestChat.library().createChat(character: character, economy: .sampleUS2005).store
        let start = try store.character().currentDate
        var settings = SessionSettings(); settings.household = .familySupported; settings.contextLookupMode = .off
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        try store.updateFiscalOverride(jurisdiction: japan,
            values: .init(incomeTaxBasisPoints: 1234, accountingUnitsPerLocalUnit: 0.01), expectedRevision: store.revision())
        try store.updateBusinessSimulation(businessChanges: [.init(action: .create, id: "remote", name: "Remote company",
            accountId: "remote", jurisdiction: .init(countryID: "US", subdivisionID: "US-TX", locality: "Houston"),
            effectiveFrom: start.iso)], obligationChanges: ["Nora", "Ali"].enumerated().map { index, name in
                .init(action: .start, id: "employee_\(index)", businessId: "remote", kind: .payroll, name: name,
                      monthlyMinor: 1_000_000, fromAccountId: "remote",
                      jurisdiction: .init(countryID: "US", subdivisionID: "US-TX", locality: index == 0 ? "Austin" : "Dallas"),
                      taxResidence: .init(countryID: "JP", subdivisionID: "JP-13", locality: index == 0 ? "Tokyo" : "Shibuya"),
                      employeeBirthDate: "1990-01-01", monthlyHours: 160, effectiveFrom: start.iso)
            }, expectedRevision: store.revision())
        func profiles(_ context: String) throws -> [FiscalProfile] {
            let prefix = "Applicable fiscal profile: "
            return try context.components(separatedBy: "\n").filter { $0.hasPrefix(prefix) }.map {
                try JSONDecoder().decode(FiscalProfile.self, from: Data($0.dropFirst(prefix.count).utf8))
            }
        }
        let first = try profiles(GroundTruthBuilder.build(store: store, rules: .v1).simulationContext)
        #expect(first.count == 2)
        #expect(first.allSatisfy { $0.date == start && $0.jurisdiction.locality == nil })
        let foreign = try #require(first.first { $0.jurisdiction == japan })
        #expect(foreign.incomeBrackets.first?.rateBasisPoints == 1234)
        #expect(foreign.conversion.accountingUnitsPerLocalUnit == 0.01)

        let partial = output("Two weeks of the recorded contracts accrue.", time: .init(unit: .days, amount: 15))
        _ = try await TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(partial)]), fate: FixedFate([50]))
            .play("Continue for fifteen days.", skipTime: .init(unit: .days, amount: 15))
        let today = try store.character().currentDate
        #expect(try !store.businessSimulation().accruals.isEmpty)
        try store.updateFiscalOverride(jurisdiction: japan,
            values: .init(incomeTaxBasisPoints: 2345, accountingUnitsPerLocalUnit: 0.02), expectedRevision: store.revision())
        let truth = try GroundTruthBuilder.build(store: store, rules: .v1)
        let dated = try profiles(truth.simulationContext).filter { $0.jurisdiction == japan }
        #expect(dated.count == 2)
        #expect(dated.first { $0.date == start }?.incomeBrackets.first?.rateBasisPoints == 1234)
        #expect(dated.first { $0.date == start }?.conversion.accountingUnitsPerLocalUnit == 0.01)
        #expect(dated.first { $0.date == today }?.incomeBrackets.first?.rateBasisPoints == 2345)
        #expect(dated.first { $0.date == today }?.conversion.accountingUnitsPerLocalUnit == 0.02)
        let provider = StubProvider(responses: [StubProvider.reply(try wire())])
        _ = try await LLMNarrator(provider: provider).narrate(NarratorRequest(groundTruth: truth,
            playerInput: "Review the foreign employees' deductions.", fate: 50, targetWords: 200, recentMessages: []))
        #expect(provider.requests.count == 1)
        #expect(provider.requests[0].user.contains("JP-13"))
        #expect(provider.requests[0].user.contains("\"rateBasisPoints\":1234") && provider.requests[0].user.contains("\"rateBasisPoints\":2345"))
    }
}
