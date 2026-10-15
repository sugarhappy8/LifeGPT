import Foundation

// MARK: Wealth and economy

public enum WealthTier: String, Codable, CaseIterable, Sendable {
    case destitute, poor, working, middle, comfortable, wealthy, ultraWealthy
}

public struct WageBand: Codable, Equatable, Sendable {
    public var name: String
    public var minMonthlyMinor: Int64
    public var maxMonthlyMinor: Int64

    public init(name: String, minMonthlyMinor: Int64, maxMonthlyMinor: Int64) {
        self.name = name
        self.minMonthlyMinor = minMonthlyMinor
        self.maxMonthlyMinor = maxMonthlyMinor
    }
}

/// What money means in this chat's place and era. Amounts are minor units
/// (for example cents). Every money rule scales from `medianMonthlyIncomeMinor`.
public struct EconomyCard: Codable, Equatable, Sendable {
    public var currency: String
    public var minorUnitsPerUnit: Int
    public var wageBands: [WageBand]
    public var medianMonthlyIncomeMinor: Int64
    public var monthlyLivingCostMinor: Int64
    public var version: Int

    public init(currency: String, minorUnitsPerUnit: Int, wageBands: [WageBand],
                medianMonthlyIncomeMinor: Int64, monthlyLivingCostMinor: Int64, version: Int) {
        self.currency = currency
        self.minorUnitsPerUnit = minorUnitsPerUnit
        self.wageBands = wageBands
        self.medianMonthlyIncomeMinor = medianMonthlyIncomeMinor
        self.monthlyLivingCostMinor = monthlyLivingCostMinor
        self.version = version
    }

    /// Fixture used by tests and the mock CLI until the Setup Generator exists.
    public static let sampleUS2005 = EconomyCard(
        currency: "USD",
        minorUnitsPerUnit: 100,
        wageBands: [
            WageBand(name: "entry", minMonthlyMinor: 140_000, maxMonthlyMinor: 230_000),
            WageBand(name: "skilled", minMonthlyMinor: 230_000, maxMonthlyMinor: 450_000),
            WageBand(name: "professional", minMonthlyMinor: 450_000, maxMonthlyMinor: 900_000),
        ],
        medianMonthlyIncomeMinor: 350_000,
        monthlyLivingCostMinor: 120_000,
        version: 1
    )
}

// MARK: Money sources

public enum SourceType: String, Codable, Sendable {
    case opening
    case wage
    case sideHustle = "side_hustle"
    case businessProfit = "business_profit"
    case investment
    case assetSale = "asset_sale"
    case loan
    case gift
    case inheritance
    case windfall
    case crime
    case expense
    case livingCost = "living_cost"
}

// MARK: Character

public struct NewCharacter: Equatable, Sendable {
    public var name: String
    public var birthplace: String
    public var birthYear: Int
    public var appearance: String
    public var startingAge: Int
    public var background: String?
    public var familyWealthTier: WealthTier
    public var swingDial: Int
    public var replyLengthWords: Int

    public init(name: String, birthplace: String, birthYear: Int, appearance: String,
                startingAge: Int, background: String?,
                familyWealthTier: WealthTier = .middle, swingDial: Int = 1, replyLengthWords: Int = 200) {
        self.name = name
        self.birthplace = birthplace
        self.birthYear = birthYear
        self.appearance = appearance
        self.startingAge = startingAge
        self.background = background
        self.familyWealthTier = familyWealthTier
        self.swingDial = swingDial
        self.replyLengthWords = replyLengthWords
    }
}

public struct Character: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var birthplace: String
    public var birthYear: Int
    public var appearance: String
    public var startingAge: Int
    public var background: String?
    public var familyWealthTier: WealthTier
    public var swingDial: Int
    public var replyLengthWords: Int
    public var birthDate: GameDate
    /// Settable so tests can start mid-year.
    public var currentDate: GameDate

    public var ageYears: Int { currentDate.ageYears(bornOn: birthDate) }

    /// Birth date is assumed to be Jan 1 of the birth year; the story starts on
    /// Jan 1 of (birth year + starting age).
    public init(from new: NewCharacter, id: UUID = UUID()) {
        self.id = id
        name = new.name
        birthplace = new.birthplace
        birthYear = new.birthYear
        appearance = new.appearance
        startingAge = new.startingAge
        background = new.background
        familyWealthTier = new.familyWealthTier
        swingDial = new.swingDial
        replyLengthWords = new.replyLengthWords
        birthDate = GameDate(year: new.birthYear, month: 1, day: 1)
        currentDate = GameDate(year: new.birthYear + new.startingAge, month: 1, day: 1)
    }
}

// MARK: Money helpers

public enum Money {
    /// Formats minor units as `1,234.56 USD` (no locale dependence).
    public static func format(_ minor: Int64, economy: EconomyCard) -> String {
        let magnitude = minor.magnitude
        let unit = UInt64(max(economy.minorUnitsPerUnit, 1))
        let whole = magnitude / unit
        let fraction = magnitude % unit

        var text = groupThousands(String(whole))
        if unit > 1 {
            let digits = String(unit - 1).count
            let f = String(fraction)
            text += "." + String(repeating: "0", count: max(0, digits - f.count)) + f
        }
        return (minor < 0 ? "-" : "") + text + " " + economy.currency
    }

    private static func groupThousands(_ digits: String) -> String {
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }
}

public enum StartingMoney {
    /// 2% of the median monthly income under 13, 10% for 13–17, 50% from 18.
    public static func balanceMinor(forAge age: Int, economy: EconomyCard) -> Int64 {
        let percent: Int64 = age < 13 ? 2 : (age < 18 ? 10 : 50)
        return economy.medianMonthlyIncomeMinor * percent / 100
    }
}
