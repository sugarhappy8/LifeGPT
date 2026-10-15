import Foundation

/// A narrator backed by an AI provider: renders the prompt, calls the
/// provider, and decodes the structured reply.
public struct LLMNarrator: Narrator {
    private let provider: any AIProvider
    private let maxOutputTokens: Int

    /// 16,000 because thinking tokens count toward the limit on some models.
    public init(provider: any AIProvider, maxOutputTokens: Int = 16_000) {
        self.provider = provider
        self.maxOutputTokens = maxOutputTokens
    }

    public func narrate(_ request: NarratorRequest) async throws -> NarratorResult {
        try await call(request, rejections: [])
    }

    public func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult {
        try await call(request, rejections: rejections)
    }

    private func call(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult {
        let prompt = PromptRenderer.render(request, rejections: rejections)
        let response = try await provider.complete(ProviderRequest(
            system: prompt.system, user: prompt.user, maxOutputTokens: maxOutputTokens,
            jsonSchema: provider.capabilities.supportsJSONSchema ? OutputSchema.json : nil))

        switch response.stopReason {
        case .refusal: throw NarratorError.refused
        case .maxTokens: throw NarratorError.truncated
        case .endTurn, .other: break
        }

        do {
            let output = try OutputCoding.decoder.decode(TurnOutput.self, from: Data(Self.jsonObject(in: response.text).utf8))
            return NarratorResult(output: output, inputTokens: response.inputTokens, outputTokens: response.outputTokens)
        } catch {
            throw NarratorError.malformedOutput(String(String(describing: error).prefix(200)))
        }
    }

    /// Models without schema enforcement sometimes wrap the JSON in code fences
    /// or chatter; take everything from the first `{` to the last `}`.
    static func jsonObject(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }
}
