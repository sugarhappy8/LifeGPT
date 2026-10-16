import Foundation

/// LM Studio and Ollama's common /v1/chat/completions surface. No cloud fallback.
public struct LocalProvider: AIProvider {
    private let endpoint: URL
    private let model: String
    private let transport: any HTTPTransport
    public let capabilities: ProviderCapabilities
    public init(baseURL: URL, model: String, contextTokens: Int = 32_768, structuredOutput: Bool = false,
                transport: any HTTPTransport = PrivateHTTPTransport.shared) throws {
        guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""), baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else {
            throw ValidationError.invalid("Enter an HTTP or HTTPS local server URL, without credentials, a query, or a fragment.")
        }
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError.invalid("Enter the exact loaded local model name.") }
        var root = baseURL
        if root.path.isEmpty || root.path == "/" { root.appendPathComponent("v1") }
        self.endpoint = root.appendingPathComponent("chat/completions")
        self.model = model; self.transport = transport
        self.capabilities = ProviderCapabilities(maxContextTokens: contextTokens, supportsJSONSchema: structuredOutput,
            supportsToolCalls: false, supportsCaching: false, supportsStreaming: false)
    }
    public func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        var body: [String: Any] = ["model": model, "stream": false, "max_tokens": request.maxOutputTokens,
            "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.user]]]
        if capabilities.supportsJSONSchema, let schema = request.jsonSchema {
            body["response_format"] = ["type": "json_schema", "json_schema": ["name": "life_turn", "strict": true,
                "schema": try JSONSerialization.jsonObject(with: Data(schema.utf8))]]
        }
        var http = URLRequest(url: endpoint); http.httpMethod = "POST"; http.timeoutInterval = 600
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.send(http)
        try HTTPResponseCheck.validate(data, response: response, secrets: [])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw ProviderError.badResponse }
        let reason = choice["finish_reason"] as? String ?? ""
        let refused = (message["refusal"] as? String)?.isEmpty == false
        let stop: StopReason = refused || reason == "content_filter" ? .refusal : reason == "length" ? .maxTokens : .endTurn
        let text = message["content"] as? String ?? ""
        guard !text.isEmpty || stop == .refusal else { throw ProviderError.badResponse }
        let usage = root["usage"] as? [String: Any] ?? [:]
        return ProviderResponse(text: text, stopReason: stop,
            inputTokens: usage["prompt_tokens"] as? Int ?? ContextBuilder.estimatedTokens(request.system + request.user),
            outputTokens: usage["completion_tokens"] as? Int ?? ContextBuilder.estimatedTokens(text))
    }
}
