import Foundation
import Testing
@testable import LifeCore

private let secret = "sk-ant-test-SECRET-123"

private func provider(_ transport: StubTransport, model: String = "claude-opus-5-5", effort: String = "medium",
                      fallback: Bool = true) -> AnthropicProvider {
    AnthropicProvider(apiKey: secret, model: model, effort: effort, useRefusalFallback: fallback, transport: transport)
}

private let sample = ProviderRequest(system: "SYS", user: "USER", maxOutputTokens: 16_000, jsonSchema: OutputSchema.json)

@Suite struct AnthropicProviderTests {
    @Test func buildsExpectedRequest() async throws {
        let transport = StubTransport(body: okResponse)
        _ = try await provider(transport).complete(sample)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == secret)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(request.timeoutInterval == 600)

        let body = try transport.lastBody()
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["max_tokens"] as? Int == 16_000)
        #expect(body["system"] as? String == "SYS")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user"); #expect(messages[0]["content"] as? String == "USER")
        let config = try #require(body["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "medium")
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["schema"] as? [String: Any])?["required"] as? [String] == ["resolution", "narration", "author_notes", "choices"])
    }

    @Test func usesConfiguredModelAndEffortAndOmitsFormatWithoutSchema() async throws {
        let transport = StubTransport(body: okResponse)
        _ = try await provider(transport, model: "claude-sonnet-5-5", effort: "low")
            .complete(ProviderRequest(system: "S", user: "U", maxOutputTokens: 100, jsonSchema: nil))
        let body = try transport.lastBody()
        #expect(body["model"] as? String == "claude-sonnet-5-5")
        let config = try #require(body["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "low"); #expect(config["format"] == nil)
    }

    @Test func neverSendsParametersThatOpus55Rejects() async throws {
        let transport = StubTransport(body: okResponse)
        _ = try await provider(transport).complete(sample)
        let body = try transport.lastBody()
        for forbidden in ["thinking", "temperature", "top_p", "top_k", "tool_choice"] {
            #expect(body[forbidden] == nil, "\(forbidden) must not be sent")
        }
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.last?["role"] as? String == "user")   // no assistant prefill
    }

    @Test func refusalFallbackIsOnByDefaultAndCanBeDisabled() async throws {
        let on = StubTransport(body: okResponse)
        _ = try await provider(on).complete(sample)
        #expect(try on.lastBody()["fallbacks"] as? String == "default")
        #expect(on.requests[0].value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let off = StubTransport(body: okResponse)
        _ = try await provider(off, fallback: false).complete(sample)
        #expect(try off.lastBody()["fallbacks"] == nil)
        #expect(off.requests[0].value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func parsesTextIgnoringThinkingBlocksAndReadsUsage() async throws {
        let body = """
        { "content": [ { "type": "thinking", "thinking": "", "signature": "x" },
                       { "type": "text", "text": "Hello, " }, { "type": "text", "text": "world." } ],
          "stop_reason": "end_turn", "usage": { "input_tokens": 12, "output_tokens": 34 } }
        """
        let response = try await provider(StubTransport(body: body)).complete(sample)
        #expect(response.text == "Hello, world."); #expect(response.stopReason == .endTurn)
        #expect(response.inputTokens == 12); #expect(response.outputTokens == 34)
    }

    @Test func mapsStopReasons() async throws {
        func stop(_ raw: String) async throws -> StopReason {
            let body = #"{ "content": [], "stop_reason": "\#(raw)", "usage": { "input_tokens": 1, "output_tokens": 1 } }"#
            return try await provider(StubTransport(body: body)).complete(sample).stopReason
        }
        #expect(try await stop("max_tokens") == .maxTokens)
        #expect(try await stop("refusal") == .refusal)
        #expect(try await stop("tool_use") == .other("tool_use"))
    }

    @Test func httpErrorsSurfaceStatusAndRedactTheKey() async throws {
        let transport = StubTransport(status: 401, body: #"{"error":{"message":"invalid key \#(secret)"}}"#)
        do {
            _ = try await provider(transport).complete(sample)
            Issue.record("expected an error")
        } catch let ProviderError.http(status, body) {
            #expect(status == 401); #expect(body.contains("[redacted]")); #expect(!body.contains(secret))
        }
        let rateLimited = StubTransport(status: 429, body: "{}")
        await #expect(throws: ProviderError.self) { _ = try await provider(rateLimited).complete(sample) }
    }

    @Test func nonJSONSuccessIsABadResponse() async throws {
        let transport = StubTransport(body: "<html>oops</html>")
        do { _ = try await provider(transport).complete(sample); Issue.record("expected an error") }
        catch ProviderError.badResponse {}
    }

    @Test func providerNeverPrintsItsKey() {
        let p = provider(StubTransport(body: okResponse))
        #expect(!String(describing: p).contains(secret)); #expect(!String(reflecting: p).contains(secret))
    }

    @Test func capabilitiesReflectWhatTheAdapterImplements() {
        let c = provider(StubTransport(body: okResponse)).capabilities
        #expect(c.maxContextTokens == 1_000_000); #expect(c.supportsJSONSchema)
        #expect(c.prefersFlatResponseSchema)
        #expect(!c.supportsToolCalls); #expect(!c.supportsCaching); #expect(!c.supportsStreaming)
    }

    @Test func endToEndWithLLMNarrator() async throws {
        let json = """
        { "resolution": { "zoom": "scene", "time_advance": { "unit": "days", "amount": 0 }, "money": [],
          "income_streams": [], "decisions": [], "life_state_changes": [], "cast_updates": [], "events": [] },
          "narration": "You look around." }
        """
        let envelope = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": json]], "stop_reason": "end_turn",
            "usage": ["input_tokens": 5, "output_tokens": 6]])
        let transport = StubTransport(body: String(decoding: envelope, as: UTF8.self))
        let store = try TestChat.chat(try TestChat.library()).store
        let processor = TurnProcessor(store: store, narrator: LLMNarrator(provider: provider(transport)), fate: FixedFate([50]))
        let result = try await processor.play("I look around.")
        #expect(result.text == "You look around.")
        #expect(try store.turnLogs().last?.inputTokens == 5)
        let body = try transport.lastBody()
        #expect((body["messages"] as? [[String: Any]])?[0]["content"] as? String != nil)
        let config = try #require(body["output_config"] as? [String: Any])
        let format = try #require(config["format"] as? [String: Any])
        let schema = try #require(format["schema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect((properties["resolution"] as? [String: Any])?["type"] as? String == "string")
        #expect(((body["messages"] as? [[String: Any]])?[0]["content"] as? String)?.contains(OutputSchema.json) == true)
    }
}
