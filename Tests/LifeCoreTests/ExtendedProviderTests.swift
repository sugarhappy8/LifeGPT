import Foundation
import Testing
@testable import LifeCore

@Suite struct ExtendedProviderTests {
    let request = ProviderRequest(system: "System", user: "User", maxOutputTokens: 2048, jsonSchema: #"{"type":"object","properties":{}}"#)

    @Test func geminiUsesHeaderAuthenticationAndStructuredFormat() async throws {
        let transport = StubTransport(body: #"{"candidates":[{"content":{"parts":[{"text":"secret thinking","thought":true},{"text":"{}"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":20,"thoughtsTokenCount":30}}"#)
        let response = try await GeminiProvider(apiKey: "test-secret", transport: transport).complete(request)
        #expect(response.text == "{}"); #expect(response.outputTokens == 50)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "x-goog-api-key") == "test-secret")
        #expect(transport.requests.last?.url?.query == nil)
        let body = try transport.lastBody()
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseFormat"] != nil)
        #expect(config["maxOutputTokens"] as? Int == 2048)
    }
    @Test func geminiMapsBlockedAndTruncatedReplies() async throws {
        let blocked = StubTransport(body: #"{"promptFeedback":{"blockReason":"SAFETY"}}"#)
        #expect(try await GeminiProvider(apiKey: "k", transport: blocked).complete(request).stopReason == .refusal)
        let cut = StubTransport(body: #"{"candidates":[{"content":{"parts":[{"text":"partial"}]},"finishReason":"MAX_TOKENS"}]}"#)
        #expect(try await GeminiProvider(apiKey: "k", transport: cut).complete(request).stopReason == .maxTokens)
    }
    @Test func localNormalizesEndpointAndDoesNotSendAKey() async throws {
        let transport = StubTransport(body: #"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":1}}"#)
        let provider = try LocalProvider(baseURL: URL(string: "http://localhost:11434")!, model: "story-model", transport: transport)
        let response = try await provider.complete(request)
        #expect(response.text == "OK")
        #expect(transport.requests.last?.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try transport.lastBody()["response_format"] == nil)
        #expect(!provider.capabilities.supportsJSONSchema)
    }
    @Test func localSchemaIsOptInAndInvalidURLsFailEarly() async throws {
        let transport = StubTransport(body: #"{"choices":[{"message":{"content":"{}"},"finish_reason":"stop"}]}"#)
        let provider = try LocalProvider(baseURL: URL(string: "http://localhost:1234/v1")!, model: "story", structuredOutput: true, transport: transport)
        _ = try await provider.complete(request)
        #expect(try transport.lastBody()["response_format"] != nil)
        for url in ["file:///tmp/model", "https://user:password@localhost/v1", "http://localhost/v1?key=secret"] {
            #expect(throws: ValidationError.self) { _ = try LocalProvider(baseURL: URL(string: url)!, model: "story") }
        }
    }
    @Test func providerErrorsRedactSecretsBeforeTruncating() async {
        let secret = "sensitive-key-for-testing"
        let transport = StubTransport(status: 400, body: String(repeating: "x", count: 790) + secret)
        do { _ = try await GeminiProvider(apiKey: secret, transport: transport).complete(request); Issue.record("Expected rejection") }
        catch { #expect(!error.localizedDescription.contains("sensitive")) }
    }
    @Test func localTwoStepHoldsDraftAndExtractsACompleteResolution() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        let provider = StubProvider(responses: [.success(ProviderResponse(text: "An unvalidated draft.", stopReason: .endTurn, inputTokens: 10, outputTokens: 20)),
            StubProvider.reply(String(decoding: try OutputCoding.encoder.encode(output("A validated scene.")), as: UTF8.self))])
        provider.capabilities.supportsJSONSchema = false
        let narrator = LLMNarrator(provider: provider, mode: .twoStep)
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        _ = try await processor.play("I walk outside.")
        #expect(provider.requests.count == 2)
        #expect(provider.requests[1].user.contains("draft_to_validate"))
        #expect(provider.requests[1].user.contains("JSON contract"))
        #expect(try store.recentMessages(limit: 10).last?.text == "A validated scene.")
        #expect(try store.turnLogs().last?.inputTokens == 1010)
    }
    @Test func usageReservationsEnforceLimitAndPersistAllResponses() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("usage.json")
        let tracker = try UsageTracker(url: url)
        let id = try await tracker.reserve(estimatedUSD: 0.7, dailyLimit: 1)
        await #expect(throws: ValidationError.self) { _ = try await tracker.reserve(estimatedUSD: 0.4, dailyLimit: 1) }
        try await tracker.record(UsageRecord(id: UUID(), date: Date(), provider: "test", model: "model", inputTokens: 10, outputTokens: 10, estimatedUSD: 0.2), reservation: id)
        let next = try await tracker.reserve(estimatedUSD: 0.7, dailyLimit: 1)
        await tracker.release(next)
        let reopened = try UsageTracker(url: url)
        #expect(await reopened.history().count == 1)
        #expect(await reopened.todayCost() == 0.2)
    }
    @Test func meteringRecordsUnusableOutputBeforeNarratorValidation() async throws {
        let provider = StubProvider(responses: [StubProvider.reply("not JSON")])
        let tracker = try UsageTracker(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("usage.json"))
        let metered = MeteredProvider(base: provider, tracker: tracker, providerName: "test", model: "test", inputUSDPerMillion: 1, outputUSDPerMillion: 2, dailyLimit: 1)
        let result = try await metered.complete(request)
        #expect(result.text == "not JSON")
        #expect(await tracker.history().count == 1)
    }
}

@Suite struct WorldGeneratorTests {
    @Test func updatedWorldRetainsCurrencyAndRequiresReviewBeforeWriting() async throws {
        let economy = EconomyCard.sampleUS2005
        let draft = WorldDraft(brief: "A changed city, with approximate prices for the new era.", economy: economy)
        let text = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
        let provider = StubProvider(responses: [StubProvider.reply(text)])
        let store = try TestChat.chat(try TestChat.library()).store
        let generated = try await WorldGenerator(provider: provider).generate(location: "New York", character: store.character(), economy: economy)
        #expect(generated == draft)
        #expect(try store.placeTimeBriefs().isEmpty)
        #expect(try store.economy().version == 1)
        var wrong = draft; wrong.economy.currency = "EUR"
        #expect(throws: ValidationError.self) { try wrong.validate(accountingCurrency: economy) }
    }
}
