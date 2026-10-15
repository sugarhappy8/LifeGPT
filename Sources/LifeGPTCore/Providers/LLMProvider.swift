import Foundation

/// One request to a model: a system prompt, a single user message, and optionally a JSON Schema the reply must follow.
public struct LLMRequest: Sendable {
    public var system: String
    public var user: String
    public var jsonSchema: JSONValue?
    public var maxTokens: Int

    public init(system: String, user: String, jsonSchema: JSONValue? = nil, maxTokens: Int = 16_000) {
        self.system = system
        self.user = user
        self.jsonSchema = jsonSchema
        self.maxTokens = maxTokens
    }
}

/// The seam that keeps the model provider swappable. The engine only ever talks to this protocol.
public protocol LLMProvider: Sendable {
    /// Returns the model's text reply (JSON text when `jsonSchema` is set).
    func complete(_ request: LLMRequest) async throws -> String
}

/// Providers the app knows how to build. Add a case and an implementation to support another vendor.
public enum ProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case anthropic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        }
    }

    public var models: [String] {
        switch self {
        case .anthropic: return ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        }
    }

    public var defaultModel: String { models[0] }

    public func makeProvider(apiKey: String, model: String) -> LLMProvider {
        switch self {
        case .anthropic: return AnthropicProvider(apiKey: apiKey, model: model)
        }
    }
}
