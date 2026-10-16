import Foundation
import Testing
@testable import LifeCore

@Suite struct SchemaComplexityTests {
    // Even a wide zero-optional turn schema failed live compilation. Keep the
    // actual constrained schema flat; the full logical contract travels in the prompt.
    // https://platform.claude.com/docs/en/build-with-claude/structured-outputs#schema-complexity-limits
    @Test func claudeTransportSchemaStaysFlatWithNoOptionalBranches() throws {
        let schema = try JSONSerialization.jsonObject(with: Data(OutputSchema.flatEnvelopeJSON.utf8))
        var optionals = 0, unions = 0, objects = 0
        func visit(_ value: Any) {
            if let object = value as? [String: Any] {
                if let properties = object["properties"] as? [String: Any] {
                    let required = Set(object["required"] as? [String] ?? [])
                    let count = Set(properties.keys).subtracting(required).count
                    optionals += count; objects += 1
                }
                if object["anyOf"] != nil || object["type"] is [String] { unions += 1 }
                for child in object.values { visit(child) }
            } else if let array = value as? [Any] { for child in array { visit(child) } }
        }
        visit(schema)
        #expect(optionals == 0 && unions == 0 && objects == 1)
        #expect(OutputSchema.flatEnvelopeJSON.utf8.count < 1024)
    }

    @Test func unusedSystemsHaveExplicitSafeDefaultsWithoutFabricatingCrimeOrCastFields() async throws {
        let json = #"""
        {"resolution":{"zoom":"scene","time_advance":{"unit":"days","amount":0},
        "money":[],"income_streams":[],"decisions":[],"life_state_changes":[],"cast_updates":[],"events":[],
        "path_updates":[],"thread_updates":[],"financial_actions":[],"account_openings":[],"transfers":[],
        "life_ended":false,"crime_attempt":null},"narration":"You open the university letters.","author_notes":"","choices":[]}
        """#
        let schema = try #require(JSONSerialization.jsonObject(with: Data(OutputSchema.json.utf8)) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let resolution = try #require(properties["resolution"] as? [String: Any])
        let fields = try #require(resolution["properties"] as? [String: Any])
        let required = Set(try #require(resolution["required"] as? [String]))
        #expect(required == Set(fields.keys).subtracting(["crime_attempt"]))
        let cast = try #require(fields["cast_updates"] as? [String: Any])
        let person = try #require(cast["items"] as? [String: Any])
        #expect(person["required"] as? [String] == ["name"])

        let store = try TestChat.chat(TestChat.library()).store
        let balance = try store.balanceMinor()
        let date = try store.character().currentDate
        let provider = StubProvider(responses: [StubProvider.reply(json)])
        let processor = TurnProcessor(store: store, narrator: LLMNarrator(provider: provider), fate: FixedFate([1]))
        _ = try await processor.play("I open the university letters.")
        #expect(provider.requests.count == 1)
        #expect(try store.balanceMinor() == balance && store.character().currentDate == date)
        #expect(try store.castMembers().isEmpty && store.incomeStreams().isEmpty)
        #expect(try store.accounts().count == 1 && store.events(limit: 20).isEmpty)
        #expect(try store.positions().isEmpty && !store.hasEnded())
    }

    @Test func completeIncomeFieldsRetainEndSemantics() async throws {
        let store = try TestChat.chat(TestChat.library()).store
        let setup = IncomeStreamChange(action: .start, name: "Website", kind: .business, tier: nil,
            monthlyMinor: 5_000_000, reason: "Established business")
        try BankingEngine.manage(store: store, openings: [], changes: [setup], transfers: [], expectedRevision: 0)
        var settings = SessionSettings(); settings.household = .familySupported
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        let ending = output("The website stops earning.", time: .init(unit: .months, amount: 1), streams: [
            .init(action: .end, name: "Website", kind: .business, tier: nil, monthlyMinor: 5_000_000,
                  accountId: "personal", effectiveFrom: TestChat.date.iso, reason: "The business closes")])
        let narrator = ScriptedNarrator(narrate: [.output(ending)])
        _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50])).play("I close the website and wait one month.")
        #expect(try store.incomeStreams().first?.endedOn == TestChat.date)
        #expect(try store.balanceMinor() == 175_000)
        #expect(narrator.repairCalls == 0)
    }

    @Test func providerGrammarFailureWritesNothingAndDoesNotStartARepairLoop() async throws {
        let transport = StubTransport(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"The compiled grammar is too large, which would cause performance issues. Simplify your tool schemas or reduce the number of strict tools."}}"#)
        let store = try TestChat.chat(TestChat.library()).store
        let revision = try store.revision(), balance = try store.balanceMinor()
        let provider = AnthropicProvider(apiKey: "test-key", model: "claude-sonnet-5-5", transport: transport)
        let processor = TurnProcessor(store: store, narrator: LLMNarrator(provider: provider), fate: FixedFate([50]))
        await #expect(throws: ProviderError.self) {
            _ = try await processor.play("Record USD 50,000 monthly website profit.")
        }
        #expect(transport.requests.count == 1)
        #expect(try store.revision() == revision && store.balanceMinor() == balance)
        #expect(try store.recentMessages(limit: 20).isEmpty && store.incomeStreams().isEmpty)
    }
}
