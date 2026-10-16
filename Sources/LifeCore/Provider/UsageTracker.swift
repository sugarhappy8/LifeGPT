import Foundation

public struct UsageRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var provider: String
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var estimatedUSD: Double
    public var purpose: String? = nil
}

/// Tracks every successful API response, including repairs, rejected JSON and setup calls.
/// Conservative reservations prevent concurrent requests from bypassing the configured estimate limit.
public actor UsageTracker {
    private let url: URL
    private var records: [UsageRecord]
    private var reservations: [UUID: Double] = [:]
    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            records = try JSONDecoder().decode([UsageRecord].self, from: Data(contentsOf: url))
        } else { records = [] }
    }
    public func history() -> [UsageRecord] { records }
    public func todayCost() -> Double {
        records.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.estimatedUSD }
    }
    public func reserve(estimatedUSD: Double, dailyLimit: Double) throws -> UUID {
        guard estimatedUSD.isFinite, estimatedUSD >= 0 else { throw ValidationError.invalid("Invalid price configuration.") }
        if dailyLimit > 0, todayCost() + reservations.values.reduce(0, +) + estimatedUSD > dailyLimit {
            throw ValidationError.invalid("This request could exceed your estimated daily spending limit. Adjust the limit or output length in Settings.")
        }
        let id = UUID(); reservations[id] = estimatedUSD; return id
    }
    public func release(_ id: UUID) { reservations[id] = nil }
    public func record(_ record: UsageRecord, reservation id: UUID) throws {
        reservations[id] = nil
        records.append(record)
        let data = try JSONEncoder().encode(records)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public struct MeteredProvider: AIProvider {
    public let base: any AIProvider
    public let tracker: UsageTracker
    public let providerName: String
    public let model: String
    public let inputUSDPerMillion: Double
    public let outputUSDPerMillion: Double
    public let dailyLimit: Double
    public var capabilities: ProviderCapabilities { base.capabilities }
    public init(base: any AIProvider, tracker: UsageTracker, providerName: String, model: String,
                inputUSDPerMillion: Double, outputUSDPerMillion: Double, dailyLimit: Double) {
        self.base = base; self.tracker = tracker; self.providerName = providerName; self.model = model
        self.inputUSDPerMillion = inputUSDPerMillion; self.outputUSDPerMillion = outputUSDPerMillion; self.dailyLimit = dailyLimit
    }
    public func complete(_ request: ProviderRequest) async throws -> ProviderResponse {
        let inputEstimate = ContextBuilder.estimatedTokens(request.system + request.user + (request.jsonSchema ?? "")) + 1000
        let estimate = (Double(inputEstimate) * inputUSDPerMillion + Double(request.maxOutputTokens) * outputUSDPerMillion) / 1_000_000
        let id = try await tracker.reserve(estimatedUSD: estimate, dailyLimit: dailyLimit)
        do {
            let response = try await base.complete(request)
            let cost = (Double(response.inputTokens) * inputUSDPerMillion + Double(response.outputTokens) * outputUSDPerMillion) / 1_000_000
            try await tracker.record(UsageRecord(id: UUID(), date: Date(), provider: providerName, model: model,
                inputTokens: response.inputTokens, outputTokens: response.outputTokens, estimatedUSD: cost, purpose: request.purpose), reservation: id)
            return response
        } catch {
            await tracker.release(id); throw error
        }
    }
}
