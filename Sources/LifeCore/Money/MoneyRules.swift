/// What the narrator may be told is plausible right now, in minor units.
public struct Guardrails: Equatable, Sendable {
    public var sideHustleCapMinor: Int64
    public var giftCapMinor: Int64
    public var windfallCapMinor: Int64
    public var singleEntryBoundMinor: Int64
    public var windfallMinFate: Int

    public init(sideHustleCapMinor: Int64, giftCapMinor: Int64, windfallCapMinor: Int64,
                singleEntryBoundMinor: Int64, windfallMinFate: Int) {
        self.sideHustleCapMinor = sideHustleCapMinor
        self.giftCapMinor = giftCapMinor
        self.windfallCapMinor = windfallCapMinor
        self.singleEntryBoundMinor = singleEntryBoundMinor
        self.windfallMinFate = windfallMinFate
    }
}

/// The v1 money constants. Everything scales from the Economy card's
/// `medianMonthlyIncomeMinor` ("median").
public struct MoneyRules: Equatable, Sendable {
    /// Side-hustle cap = median × max(elapsedDays, this) / 60 (half a median per 30 days).
    public var sideHustleMinWindowDays = 7
    public var giftMinGapDays = 90
    public var windfallMinFate = 95
    public var windfallCapFactor: Int64 = 6
    public var windfallMinGapDays = 730
    public var singleEntryBoundFactor: Int64 = 12
    /// Gift cap = median × percent / 100, by the family's wealth tier.
    public var giftTierPercent: [WealthTier: Int64] = [
        .destitute: 10, .poor: 25, .working: 50, .middle: 100,
        .comfortable: 200, .wealthy: 400, .ultraWealthy: 800,
    ]

    public static let v1 = MoneyRules()

    public init() {}

    public func sideHustleCap(economy: EconomyCard, elapsedDays: Int) -> Int64 {
        let days = Int64(max(elapsedDays, sideHustleMinWindowDays))
        return Self.multiply(economy.medianMonthlyIncomeMinor, days) / 60
    }

    public func selfEmploymentMonthlyCap(economy: EconomyCard) -> Int64 {
        sideHustleCap(economy: economy, elapsedDays: 30)
    }

    public func giftCap(economy: EconomyCard, familyTier: WealthTier) -> Int64 {
        Self.multiply(economy.medianMonthlyIncomeMinor, giftTierPercent[familyTier] ?? 100) / 100
    }

    public func windfallCap(economy: EconomyCard) -> Int64 {
        Self.multiply(economy.medianMonthlyIncomeMinor, windfallCapFactor)
    }

    public func singleEntryBound(economy: EconomyCard) -> Int64 {
        Self.multiply(economy.medianMonthlyIncomeMinor, singleEntryBoundFactor)
    }

    public func guardrails(economy: EconomyCard, familyTier: WealthTier, elapsedDays: Int) -> Guardrails {
        Guardrails(sideHustleCapMinor: sideHustleCap(economy: economy, elapsedDays: elapsedDays),
                   giftCapMinor: giftCap(economy: economy, familyTier: familyTier),
                   windfallCapMinor: windfallCap(economy: economy),
                   singleEntryBoundMinor: singleEntryBound(economy: economy),
                   windfallMinFate: windfallMinFate)
    }

    /// Saturating multiply so absurd Economy cards cannot trap.
    static func multiply(_ a: Int64, _ b: Int64) -> Int64 {
        let (r, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow ? Int64.max : r
    }
}
