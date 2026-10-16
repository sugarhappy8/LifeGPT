import Foundation

public enum HTTPResponseCheck {
    public static func validate(_ data: Data, response: HTTPURLResponse, secrets: [String]) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        var body = String(decoding: data, as: UTF8.self)
        for secret in secrets where !secret.isEmpty { body = body.replacingOccurrences(of: secret, with: "[redacted]") }
        throw ProviderError.http(status: response.statusCode, body: String(body.prefix(800)))
    }
}

public struct ResilientTransport: HTTPTransport {
    private let base: any HTTPTransport
    public init(base: any HTTPTransport = PrivateHTTPTransport.shared) { self.base = base }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0...2 {
            try Task.checkCancellation()
            let response = try await base.send(request)
            let code = response.1.statusCode
            guard attempt < 2, [429, 500, 502, 503, 504, 529].contains(code) else { return response }
            let suggested = Double(response.1.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(attempt + 1)
            try await Task.sleep(for: .seconds(min(10, max(0.1, suggested))))
        }
        throw ProviderError.badResponse
    }
}

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            if status == 401 || status == 403 { return "The provider rejected the credentials (HTTP \(status)). Check the API key and model access in Settings." }
            if status == 429 { return "The provider's rate or quota limit was reached. Wait a moment or check the account's quota." }
            return "The provider returned HTTP \(status): \(body)"
        case .badResponse: return "The provider returned an unreadable or empty response. Check the model name and server settings."
        }
    }
}

extension TurnError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .refused: return "The narrator declined this scene. Try a different action. Nothing was changed."
        case .narratorFailed(let detail): return "The narrator could not produce a usable reply. Nothing was changed. \(detail)"
        case .validationFailed: return "The reply couldn’t be validated. Your life was not changed."
        }
    }
    public var failureReason: String? {
        if case .validationFailed(let reasons) = self { return reasons.joined(separator: "\n") }
        return nil
    }
}

extension StoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAStore: return "This file is not a readable LifeGPT save."
        case .unsupportedSchema(let version): return "This save uses a newer format (\(version)). Open it in a newer LifeGPT version."
        case .alreadyExists: return "A file already exists at this destination. Choose another filename."
        case .corrupt(let detail): return "The save is damaged: \(detail)"
        }
    }
}
