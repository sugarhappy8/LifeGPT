import Foundation

/// In-game calendar date with month resolution. Life sims move in months and years, not seconds,
/// so this avoids Foundation calendars and time zones entirely.
public struct GameDate: Codable, Equatable, Comparable, Hashable, Sendable, CustomStringConvertible {
    public var year: Int
    /// 1...12
    public var month: Int

    public init(year: Int, month: Int) {
        let zeroBased = year * 12 + (month - 1)
        self.year = Int((Double(zeroBased) / 12).rounded(.down))
        self.month = zeroBased - self.year * 12 + 1
    }

    public func adding(months: Int) -> GameDate {
        GameDate(year: year, month: month + months)
    }

    public var monthIndex: Int { year * 12 + (month - 1) }

    public func months(until other: GameDate) -> Int { other.monthIndex - monthIndex }

    /// Whole years elapsed from `self` to `other` (an age when `self` is a birth date).
    public func yearsUntil(_ other: GameDate) -> Int {
        let m = months(until: other)
        return m >= 0 ? m / 12 : -((-m + 11) / 12)
    }

    public static func < (lhs: GameDate, rhs: GameDate) -> Bool { lhs.monthIndex < rhs.monthIndex }

    static let monthNames = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]

    public var description: String { "\(Self.monthNames[month - 1]) \(year)" }
}
