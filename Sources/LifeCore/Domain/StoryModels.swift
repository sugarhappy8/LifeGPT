import Foundation

public struct SessionSettings: Codable, Equatable, Sendable {
    public var voiceBible = ""
    public var automaticLength = false
    public var contentTone = "General audience; non-graphic conflict and romance."
    public var difficulty = 50
    public var household: HouseholdSupport = .automatic
    public var playStyle: PlayStyle = .simulation
    public var contextLookupMode: ContextLookupMode = .automatic
    public init() {}

    private enum CodingKeys: String, CodingKey { case voiceBible, automaticLength, contentTone, difficulty, household, playStyle, contextLookupMode }
    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        voiceBible = try values.decodeIfPresent(String.self, forKey: .voiceBible) ?? voiceBible
        automaticLength = try values.decodeIfPresent(Bool.self, forKey: .automaticLength) ?? automaticLength
        contentTone = try values.decodeIfPresent(String.self, forKey: .contentTone) ?? contentTone
        difficulty = min(100, max(0, try values.decodeIfPresent(Int.self, forKey: .difficulty) ?? 50))
        household = try values.decodeIfPresent(HouseholdSupport.self, forKey: .household) ?? .automatic
        playStyle = try values.decodeIfPresent(PlayStyle.self, forKey: .playStyle) ?? .simulation
        contextLookupMode = try values.decodeIfPresent(ContextLookupMode.self, forKey: .contextLookupMode) ?? .automatic
    }
}

public struct PlaceTimeBrief: Codable, Equatable, Sendable {
    public var version: Int
    public var date: GameDate
    public var location: String
    public var text: String
    public init(version: Int = 1, date: GameDate, location: String, text: String) {
        self.version = version; self.date = date; self.location = location; self.text = text
    }
}

public struct TimelineEvent: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var date: GameDate
    public var title: String
    public var importance: Importance
    public var uncanny: Bool
}

public struct ChapterSummary: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var throughMessageID: Int64
    public var date: GameDate
    public var text: String
}

public struct OpportunityPath: Codable, Equatable, Sendable, Identifiable {
    public enum Stage: String, Codable, CaseIterable, Sendable {
        case idea, capital, launch, traction, profit, abandoned
        public var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }
    public var id: String
    public var title: String
    public var stage: Stage
    public var startedOn: GameDate
    public var stageStartedOn: GameDate
    public var investedMinor: Int64
    public var notes: String
    public init(id: String, title: String, stage: Stage = .idea, startedOn: GameDate,
                stageStartedOn: GameDate? = nil, investedMinor: Int64 = 0, notes: String = "") {
        self.id = id; self.title = title; self.stage = stage; self.startedOn = startedOn
        self.stageStartedOn = stageStartedOn ?? startedOn; self.investedMinor = investedMinor; self.notes = notes
    }
}

public struct PathUpdate: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var stage: OpportunityPath.Stage
    public var notes: String
    public init(id: String, title: String, stage: OpportunityPath.Stage, notes: String = "") {
        self.id = id; self.title = title; self.stage = stage; self.notes = notes
    }
}

public struct StoryThread: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var notes: String
    public var resolved: Bool
    public init(id: String, title: String, notes: String, resolved: Bool = false) {
        self.id = id; self.title = title; self.notes = notes; self.resolved = resolved
    }
}

public struct FinancialPosition: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case asset, investment, loan, arrears }
    public var id: String
    public var name: String
    public var kind: Kind
    public var principalMinor: Int64
    public var annualRateBPS: Int
    public var monthlyPaymentMinor: Int64
    public var openedOn: GameDate
    public var accountId: String?
    public init(id: String, name: String, kind: Kind, principalMinor: Int64, annualRateBPS: Int = 0,
                monthlyPaymentMinor: Int64 = 0, openedOn: GameDate, accountId: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.principalMinor = principalMinor
        self.annualRateBPS = annualRateBPS; self.monthlyPaymentMinor = monthlyPaymentMinor; self.openedOn = openedOn
        self.accountId = accountId
    }
    public var isDebt: Bool { kind == .loan || kind == .arrears }
}

/// These are requests. Prices, loan limits, interest and payouts are decided by FinanceEngine.
public struct FinancialAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case buyAsset = "buy_asset", sellAsset = "sell_asset", invest, withdraw, borrow, repay
    }
    public var action: Kind
    public var id: String
    public var name: String
    public var amountMinor: Int64
    public var accountId: String?
    public init(action: Kind, id: String, name: String, amountMinor: Int64, accountId: String? = nil) {
        self.action = action; self.id = id; self.name = name; self.amountMinor = amountMinor
        self.accountId = accountId
    }
}

public enum ValidationError: Error, LocalizedError, Sendable, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

extension NewCharacter {
    public func validate() throws {
        for (label, value, limit) in [("Name", name, 100), ("Birthplace", birthplace, 200), ("Appearance", appearance, 4_000)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= limit else {
                throw ValidationError.invalid("\(label) is required and must be at most \(limit) characters.")
            }
        }
        guard (1...9000).contains(birthYear), (0...99).contains(startingAge),
              (0...3).contains(swingDial), (60...2000).contains(replyLengthWords),
              (background?.count ?? 0) <= 12_000 else {
            throw ValidationError.invalid("Check the birth year (1–9000), age (0–99), reply length (60–2000), and background (12,000 characters maximum).")
        }
    }
}

extension EconomyCard {
    public func validate() throws {
        guard (1...12).contains(currency.count), [1, 10, 100, 1000].contains(minorUnitsPerUnit),
              (1...1_000_000_000_000).contains(medianMonthlyIncomeMinor),
              (0...1_000_000_000_000).contains(monthlyLivingCostMinor), (1...1_000_000).contains(version),
              !wageBands.isEmpty, wageBands.count <= 20 else {
            throw ValidationError.invalid("The economy needs a currency, a positive median income, non-negative living costs, and wage bands. Amounts must be within 1 trillion minor units.")
        }
        var names = Set<String>()
        for band in wageBands {
            guard !band.name.trimmingCharacters(in: .whitespaces).isEmpty,
                  names.insert(band.name.lowercased()).inserted,
                  band.minMonthlyMinor > 0, band.maxMonthlyMinor >= band.minMonthlyMinor,
                  band.maxMonthlyMinor <= 1_000_000_000_000 else {
                throw ValidationError.invalid("Wage bands need unique names and positive minimum/maximum amounts in ascending order.")
            }
        }
    }
}

public enum CheckedMoney {
    public static func add(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (sum, overflow) = a.addingReportingOverflow(b)
        guard !overflow else { throw ValidationError.invalid("The money amount is outside the supported range.") }
        return sum
    }
    public static func fraction(_ amount: Int64, numerator: Int64, denominator: Int64) -> Int64 {
        guard amount >= 0, numerator >= 0, denominator > 0 else { return 0 }
        let value = Decimal(amount) * Decimal(numerator) / Decimal(denominator)
        if value >= Decimal(Int64.max) { return Int64.max }
        return NSDecimalNumber(decimal: value).int64Value
    }
}
