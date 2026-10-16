/// A plain Gregorian calendar date (no time zones, no `Date`), so game logic
/// never depends on the machine's clock or locale.
public struct GameDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`; returns nil for malformed or impossible dates.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...9999).contains(y), (1...12).contains(m), d >= 1, d <= GameDate.daysInMonth(year: y, month: m)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var iso: String {
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public var description: String { iso }

    public static func < (a: GameDate, b: GameDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: Arithmetic

    public func adding(days: Int) -> GameDate {
        GameDate(dayNumber: dayNumber + days)
    }

    /// Adds calendar months, clamping the day to the target month's length.
    public func adding(months: Int) -> GameDate {
        let total = year * 12 + (month - 1) + months
        let y = GameDate.floorDiv(total, 12)
        let m = total - y * 12 + 1
        return GameDate(year: y, month: m, day: min(day, GameDate.daysInMonth(year: y, month: m)))
    }

    public func daysSince(_ other: GameDate) -> Int {
        dayNumber - other.dayNumber
    }

    /// Completed years between `birth` and this date (never negative).
    public func ageYears(bornOn birth: GameDate) -> Int {
        var age = year - birth.year
        if (month, day) < (birth.month, birth.day) { age -= 1 }
        return max(age, 0)
    }

    // MARK: Calendar helpers

    static func isLeap(_ y: Int) -> Bool {
        (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar
    /// (Howard Hinnant's days_from_civil).
    var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = GameDate.floorDiv(y, 400)
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    init(dayNumber z0: Int) {
        let z = z0 + 719_468
        let era = GameDate.floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.init(year: y, month: m, day: d)
    }
}
