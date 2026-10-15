import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls the Claude Messages API over HTTPS with the player's own key.
/// Structured outputs (`output_config.format`) guarantee the reply matches the turn schema.
public struct AnthropicProvider: LLMProvider {
    public var apiKey: String
    public var model: String
    public var endpoint: URL
    public var session: URLSession

    public init(apiKey: String, model: String, endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.session = session
    }

    public func complete(_ request: LLMRequest) async throws -> String {
        guard !apiKey.isEmpty else { throw LifeGPTError.missingAPIKey }
        var http = URLRequest(url: endpoint)
        http.httpMethod = "POST"
        http.timeoutInterval = 300
        http.setValue("application/json", forHTTPHeaderField: "content-type")
        http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Server-side fallback: if a safety classifier declines, the API retries on a suitable model.
        http.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        http.httpBody = try JSONEncoder().encode(Self.body(for: request, model: model))

        let (data, response) = try await session.data(for: http)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw LifeGPTError.provider(Self.errorMessage(status: status, data: data))
        }
        return try Self.text(fromResponse: data)
    }

    static func body(for request: LLMRequest, model: String) -> JSONValue {
        var outputConfig: [String: JSONValue] = ["effort": "medium"]
        if let schema = request.jsonSchema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        return [
            "model": .string(model),
            "max_tokens": .number(Double(request.maxTokens)),
            // The system prompt is identical every turn, so cache it.
            "system": [["type": "text", "text": .string(request.system), "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": .string(request.user)]],
            "output_config": .object(outputConfig),
            "fallbacks": "default",
        ]
    }

    static func text(fromResponse data: Data) throws -> String {
        let json: JSONValue
        do { json = try JSONDecoder().decode(JSONValue.self, from: data) } catch {
            throw LifeGPTError.malformedResponse("Unreadable API response.")
        }
        switch json["stop_reason"]?.stringValue {
        case "refusal":
            let why = json["stop_details"]?["explanation"]?.stringValue ?? "Try a different action."
            throw LifeGPTError.refused(why)
        case "max_tokens":
            throw LifeGPTError.malformedResponse("The reply was cut off. Try again.")
        default:
            break
        }
        let texts = (json["content"]?.arrayValue ?? []).compactMap { block -> String? in
            block["type"]?.stringValue == "text" ? block["text"]?.stringValue : nil
        }
        guard !texts.isEmpty else { throw LifeGPTError.malformedResponse("The reply had no text.") }
        return texts.joined()
    }

    static func errorMessage(status: Int, data: Data) -> String {
        let detail = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.stringValue
        switch status {
        case 401: return "Your API key was rejected. Check it in Settings."
        case 429: return "Rate limited by the provider. Wait a moment and try again."
        case 529, 503: return "The AI service is overloaded. Try again shortly."
        default: return "API error \(status)" + (detail.map { ": \($0)" } ?? ".")
        }
    }
}
