import Foundation
@testable import LifeCore

/// An AI provider that replays canned responses and records requests.
final class StubProvider: AIProvider, @unchecked Sendable {
    var capabilities: ProviderCapabilities
    var responses: [Result<ProviderResponse, Error>]
    private(set) var requests: [ProviderRequest] = []

    init(capabilities: ProviderCapabilities = StubProvider.capable, responses: [Result<ProviderResponse, Error>]) {
        self.capabilities = capabilities
        self.responses = responses
    }

    static let capable = ProviderCapabilities(maxContextTokens: 1_000_000, supportsJSONSchema: true,
                                              supportsToolCalls: true, supportsCaching: true, supportsStreaming: true)

    static func reply(_ text: String, stop: StopReason = .endTurn) -> Result<ProviderResponse, Error> {
        .success(ProviderResponse(text: text, stopReason: stop, inputTokens: 1_000, outputTokens: 500))
    }

    func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ProviderError.badResponse }
        return try responses.removeFirst().get()
    }
}
