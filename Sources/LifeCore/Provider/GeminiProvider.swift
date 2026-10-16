import Foundation

/// generateContent REST adapter. JSON format follows the documented responseFormat.text contract.
public struct GeminiProvider: AIProvider {
    private let apiKey: String
    private let model: String
    private let transport: any HTTPTransport
    public let capabilities: ProviderCapabilities
    public init(apiKey: String, model: String = "gemini-3.8-flash", contextTokens: Int = 128_000,
                transport: any HTTPTransport = PrivateHTTPTransport.shared) {
        self.apiKey = apiKey; self.model = model; self.transport = transport
        self.capabilities = ProviderCapabilities(maxContextTokens: contextTokens, supportsJSONSchema: true,
            supportsToolCalls: false, supportsCaching: false, supportsStreaming: false)
    }
    public func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        guard !model.isEmpty, model.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ValidationError.invalid("Enter a Gemini model ID, without a URL or models/ prefix.")
        }
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var generation: [String: Any] = ["maxOutputTokens": request.maxOutputTokens]
        if let schema = request.jsonSchema {
            generation["responseFormat"] = ["text": ["mimeType": "application/json",
                "schema": try JSONSerialization.jsonObject(with: Data(schema.utf8))]]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.system]]],
            "contents": [["role": "user", "parts": [["text": request.user]]]],
            "generationConfig": generation
        ]
        var http = URLRequest(url: endpoint); http.httpMethod = "POST"; http.timeoutInterval = 240
        http.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.send(http)
        try HTTPResponseCheck.validate(data, response: response, secrets: [apiKey])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError.badResponse }
        let usage = root["usageMetadata"] as? [String: Any] ?? [:]
        let candidate = (root["candidates"] as? [[String: Any]])?.first
        let reason = candidate?["finishReason"] as? String ?? ""
        let content = candidate?["content"] as? [String: Any]
        let text = (content?["parts"] as? [[String: Any]] ?? []).filter { $0["thought"] as? Bool != true }
            .compactMap { $0["text"] as? String }.joined()
        let blocked = (root["promptFeedback"] as? [String: Any])?["blockReason"] != nil
        let stop: StopReason = blocked || ["SAFETY", "PROHIBITED_CONTENT", "RECITATION", "BLOCKLIST"].contains(reason) ? .refusal
            : reason == "MAX_TOKENS" ? .maxTokens : reason == "STOP" ? .endTurn : .other(reason)
        guard !text.isEmpty || stop == .refusal else { throw ProviderError.badResponse }
        return ProviderResponse(text: text, stopReason: stop, inputTokens: usage["promptTokenCount"] as? Int ?? 0,
            outputTokens: (usage["candidatesTokenCount"] as? Int ?? 0) + (usage["thoughtsTokenCount"] as? Int ?? 0))
    }
}
