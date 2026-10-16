import Foundation

public struct CrimeAttempt: Codable, Equatable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

/// Abstract game outcomes only. The narrator supplies no methods or payout amount.
public enum CrimeEngine {
    public struct Outcome: Sendable {
        public var money: Int64 = 0
        public var state: [LifeStateChange] = []
        public var event: EventRecord?
        public var rejection: String?
    }
    public static func resolve(_ attempt: CrimeAttempt?, age: Int, date: GameDate, fate: Int,
                               economy: EconomyCard, lastAttempt: GameDate?) -> Outcome {
        guard let attempt else { return Outcome() }
        let reason = attempt.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some models fill optional objects with empty strings. This represents no action,
        // including for children or during a cooldown, and must never cause consequences.
        guard !reason.isEmpty else { return Outcome() }
        guard reason.count <= 500 else { return Outcome(rejection: "crime_attempt.reason must be at most 500 characters. Use null when no crime was attempted.") }
        guard age >= 16 else { return Outcome(rejection: "Crime outcomes require age 16 or older.") }
        if let lastAttempt, date.daysSince(lastAttempt) < 30 { return Outcome(rejection: "Crime outcomes are limited to one attempt per 30 days.") }
        let success = fate >= 75
        return Outcome(money: success ? max(1, economy.medianMonthlyIncomeMinor / 4) : -max(1, economy.medianMonthlyIncomeMinor / 10),
            state: [LifeStateChange(key: "_engine_last_crime_date", value: date.iso),
                    LifeStateChange(key: "legal_status", value: success ? "Risk of investigation after an offense" : "Caught; a fine is owed")],
            event: EventRecord(title: success ? "An offense leaves money and the risk of consequences" : "An offense results in a fine", importance: .major, uncanny: false))
    }
}
