import Foundation

/// How requests reach the network; a stub in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.badResponse }
        return (data, http)
    }
}

/// Talks to the Anthropic Messages API over plain HTTP (there is no official
/// Swift SDK). The API key is only ever sent in the `x-api-key` header, and is
/// never printed or included in errors.
public struct AnthropicProvider: AIProvider, CustomStringConvertible, CustomDebugStringConvertible {
    private let apiKey: String
    private let model: String
    private let effort: String
    private let useRefusalFallback: Bool
    private let transport: any HTTPTransport
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// - Parameters:
    ///   - effort: `output_config.effort`; Opus 5.5 defaults to `medium` when omitted, so it is always sent.
    ///   - useRefusalFallback: asks the API to retry a refused request on a fallback model server-side.
    public init(apiKey: String, model: String = "claude-opus-5-5", effort: String = "medium",
                useRefusalFallback: Bool = true, transport: any HTTPTransport = PrivateHTTPTransport.shared) {
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
        self.useRefusalFallback = useRefusalFallback
        self.transport = transport
    }

    /// Only what this adapter implements today: structured output, no tools,
    /// caching, or streaming yet.
    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(maxContextTokens: 1_000_000, supportsJSONSchema: true,
                             supportsToolCalls: false, supportsCaching: false, supportsStreaming: false,
                             prefersFlatResponseSchema: true)
    }

    public var description: String { "AnthropicProvider(model: \(model), effort: \(effort))" }
    public var debugDescription: String { description }

    public func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        let (data, http) = try await transport.send(try urlRequest(for: request))
        try HTTPResponseCheck.validate(data, response: http, secrets: [apiKey])
        return try Self.parse(data)
    }

    // MARK: Request

    private func urlRequest(for request: ProviderRequest) throws -> URLRequest {
        var outputConfig: [String: Any] = ["effort": effort]
        if let schema = request.jsonSchema {
            outputConfig["format"] = ["type": "json_schema",
                                      "schema": try JSONSerialization.jsonObject(with: Data(schema.utf8))]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxOutputTokens,
            "system": request.system,
            "messages": [["role": "user", "content": request.user]],
            "output_config": outputConfig,
        ]
        if useRefusalFallback { body["fallbacks"] = "default" }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 600   // long turns: thinking can take minutes
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if useRefusalFallback {
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return urlRequest
    }

    // MARK: Response

    private struct APIResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        struct Usage: Decodable { let inputTokens: Int?; let outputTokens: Int? }
        let content: [Block]
        let stopReason: String?
        let usage: Usage?
    }

    private static func parse(_ data: Data) throws -> ProviderResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let api = try? decoder.decode(APIResponse.self, from: data) else { throw ProviderError.badResponse }

        let stop: StopReason
        switch api.stopReason {
        case "end_turn": stop = .endTurn
        case "max_tokens": stop = .maxTokens
        case "refusal": stop = .refusal
        case let other?: stop = .other(other)
        case nil: stop = .other("none")
        }
        let text = api.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        return ProviderResponse(text: text, stopReason: stop,
                                inputTokens: api.usage?.inputTokens ?? 0, outputTokens: api.usage?.outputTokens ?? 0)
    }
}
