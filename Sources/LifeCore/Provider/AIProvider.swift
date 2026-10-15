/// What a provider can do. The prompt budget and the narrator's mode adapt to these.
public struct ProviderCapabilities: Equatable, Sendable {
    public var maxContextTokens: Int
    public var supportsJSONSchema: Bool
    public var supportsToolCalls: Bool
    public var supportsCaching: Bool
    public var supportsStreaming: Bool

    public init(maxContextTokens: Int, supportsJSONSchema: Bool, supportsToolCalls: Bool,
                supportsCaching: Bool, supportsStreaming: Bool) {
        self.maxContextTokens = maxContextTokens
        self.supportsJSONSchema = supportsJSONSchema
        self.supportsToolCalls = supportsToolCalls
        self.supportsCaching = supportsCaching
        self.supportsStreaming = supportsStreaming
    }
}

public enum StopReason: Equatable, Sendable {
    case endTurn, maxTokens, refusal
    case other(String)
}

public struct ProviderRequest: Sendable {
    public var system: String
    public var user: String
    public var maxOutputTokens: Int
    /// A JSON Schema the reply must satisfy, when the provider supports it.
    public var jsonSchema: String?

    public init(system: String, user: String, maxOutputTokens: Int, jsonSchema: String?) {
        self.system = system
        self.user = user
        self.maxOutputTokens = maxOutputTokens
        self.jsonSchema = jsonSchema
    }
}

public struct ProviderResponse: Sendable {
    public var text: String
    public var stopReason: StopReason
    public var inputTokens: Int
    public var outputTokens: Int

    public init(text: String, stopReason: StopReason, inputTokens: Int, outputTokens: Int) {
        self.text = text
        self.stopReason = stopReason
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum ProviderError: Error, Sendable {
    case http(status: Int, body: String)
    case badResponse
}

public protocol AIProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func complete(_ request: ProviderRequest) async throws -> ProviderResponse
}
