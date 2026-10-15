import Foundation

public struct MoneyContext: Sendable {
    public var economy: EconomyCard
    public var familyTier: WealthTier
    public var balanceMinor: Int64
    public var elapsedDays: Int
    public var fate: Int
    public var castNames: Set<String>
    /// nil means there has never been a windfall.
    public var daysSinceLastWindfall: Int?
    public var daysSinceLastGiftByGiver: [String: Int]
    public var rules: MoneyRules

    public init(economy: EconomyCard, familyTier: WealthTier, balanceMinor: Int64, elapsedDays: Int,
                fate: Int, castNames: Set<String>, daysSinceLastWindfall: Int? = nil,
                daysSinceLastGiftByGiver: [String: Int] = [:], rules: MoneyRules = .v1) {
        self.economy = economy
        self.familyTier = familyTier
        self.balanceMinor = balanceMinor
        self.elapsedDays = elapsedDays
        self.fate = fate
        self.castNames = castNames
        self.daysSinceLastWindfall = daysSinceLastWindfall
        self.daysSinceLastGiftByGiver = daysSinceLastGiftByGiver
        self.rules = rules
    }
}

public enum MoneyVerdict: Equatable, Sendable {
    case accepted
    case rejected(String)
}

/// Pure checks on what the narrator proposes. The player's words never reach
/// this code as facts: only the narrator's structured output does, and only
/// what passes here is written to the ledger.
public enum MoneyValidator {
    // MARK: Money entries

    /// One verdict per entry, in order. A running balance and the per-turn
    /// windfall and gift limits carry across entries.
    public static func validate(_ entries: [ProposedMoneyEntry], in ctx: MoneyContext) -> [MoneyVerdict] {
        var balance = ctx.balanceMinor
        var windfallUsed = false
        var giftersThisTurn = Set<String>()
        return entries.map { entry in
            let verdict = check(entry, ctx: ctx, balance: balance, windfallUsed: windfallUsed,
                                giftersThisTurn: giftersThisTurn)
            if verdict == .accepted {
                balance = saturatingAdd(balance, entry.amountMinor)
                if entry.sourceType == .windfall { windfallUsed = true }
                if entry.sourceType == .gift || entry.sourceType == .inheritance,
                   let giver = entry.counterparty {
                    giftersThisTurn.insert(giver.lowercased())
                }
            }
            return verdict
        }
    }

    private static func check(_ e: ProposedMoneyEntry, ctx: MoneyContext, balance: Int64,
                              windfallUsed: Bool, giftersThisTurn: Set<String>) -> MoneyVerdict {
        let economy = ctx.economy, rules = ctx.rules

        if e.amountMinor == 0 { return .rejected("zero amount") }

        switch e.sourceType {
        case .sideHustle, .gift, .inheritance, .windfall:
            if e.amountMinor < 0 { return .rejected("wrong sign: \(e.sourceType.rawValue) must be positive") }
        case .expense:
            if e.amountMinor > 0 { return .rejected("wrong sign: an expense must be negative") }
        default:
            break
        }

        let bound = rules.singleEntryBound(economy: economy)
        if e.amountMinor.magnitude > UInt64(bound) {
            return .rejected("exceeds the plausible bound for a single entry (\(Money.format(bound, economy: economy)))")
        }

        switch e.sourceType {
        case .opening, .wage, .investment, .livingCost:
            return .rejected("engine-only source: \(e.sourceType.rawValue) is paid or charged by the game, not proposed by the narrator")

        case .businessProfit, .assetSale, .loan, .crime:
            return .rejected("not available yet: \(e.sourceType.rawValue) payouts are not supported in this version")

        case .sideHustle:
            let cap = rules.sideHustleCap(economy: economy, elapsedDays: ctx.elapsedDays)
            if e.amountMinor > cap {
                return .rejected("over the side-hustle cap of \(Money.format(cap, economy: economy)) for this period")
            }

        case .gift, .inheritance:
            guard let giver = e.counterparty,
                  ctx.castNames.contains(where: { $0.caseInsensitiveCompare(giver) == .orderedSame })
            else { return .rejected("the giver must be someone in your cast") }
            let cap = rules.giftCap(economy: economy, familyTier: ctx.familyTier)
            if e.amountMinor > cap {
                return .rejected("over the gift cap of \(Money.format(cap, economy: economy)) for this family")
            }
            if giftersThisTurn.contains(giver.lowercased()) {
                return .rejected("gap: already received a gift from \(giver) this turn")
            }
            if let days = ctx.daysSinceLastGiftByGiver.first(where: { $0.key.caseInsensitiveCompare(giver) == .orderedSame })?.value,
               days < rules.giftMinGapDays {
                return .rejected("gap: the last gift from \(giver) was \(days) days ago (minimum \(rules.giftMinGapDays))")
            }

        case .windfall:
            if ctx.fate < rules.windfallMinFate {
                return .rejected("fate roll \(ctx.fate) is below the \(rules.windfallMinFate) a windfall needs")
            }
            let cap = rules.windfallCap(economy: economy)
            if e.amountMinor > cap {
                return .rejected("over the windfall cap of \(Money.format(cap, economy: economy))")
            }
            if windfallUsed { return .rejected("gap: only one windfall per turn") }
            if let days = ctx.daysSinceLastWindfall, days < rules.windfallMinGapDays {
                return .rejected("gap: the last windfall was \(days) days ago (minimum \(rules.windfallMinGapDays))")
            }

        case .expense:
            if saturatingAdd(balance, e.amountMinor) < 0 {
                return .rejected("balance of \(Money.format(balance, economy: economy)) cannot cover this expense")
            }
        }
        return .accepted
    }

    // MARK: Income streams

    private struct StreamDraft {
        var kind: IncomeStream.Kind
        var tier: String?
        var monthlyMinor: Int64?
    }

    /// One verdict per change, in order. Changes in the same batch see each other.
    public static func validate(_ changes: [IncomeStreamChange], existing: [IncomeStream],
                                economy: EconomyCard, rules: MoneyRules) -> [MoneyVerdict] {
        var active: [String: StreamDraft] = [:]
        for s in existing where s.endedOn == nil {
            active[s.name.lowercased()] = StreamDraft(kind: s.kind, tier: s.tier, monthlyMinor: s.monthlyMinor)
        }
        return changes.map { c in
            let key = c.name.lowercased()
            switch c.action {
            case .start:
                if active[key] != nil { return .rejected("a stream named \(c.name) is already active") }
                let draft = StreamDraft(kind: c.kind ?? .wage, tier: c.tier, monthlyMinor: c.monthlyMinor)
                if let problem = problem(with: draft, economy: economy, rules: rules) { return .rejected(problem) }
                active[key] = draft
                return .accepted
            case .change:
                guard let current = active[key] else { return .rejected("unknown stream: \(c.name)") }
                let draft = StreamDraft(kind: c.kind ?? current.kind, tier: c.tier ?? current.tier,
                                        monthlyMinor: c.monthlyMinor ?? current.monthlyMinor)
                if let problem = problem(with: draft, economy: economy, rules: rules) { return .rejected(problem) }
                active[key] = draft
                return .accepted
            case .end:
                guard active[key] != nil else { return .rejected("unknown stream: \(c.name)") }
                active[key] = nil
                return .accepted
            }
        }
    }

    private static func problem(with draft: StreamDraft, economy: EconomyCard, rules: MoneyRules) -> String? {
        guard let monthly = draft.monthlyMinor else { return "missing monthly amount, so it cannot be checked against a band" }
        switch draft.kind {
        case .wage:
            guard let tier = draft.tier,
                  let band = economy.wageBands.first(where: { $0.name.caseInsensitiveCompare(tier) == .orderedSame })
            else { return "unknown or missing wage tier (no matching band)" }
            if monthly < band.minMonthlyMinor || monthly > band.maxMonthlyMinor {
                return "outside the \(band.name) band (\(Money.format(band.minMonthlyMinor, economy: economy)) to \(Money.format(band.maxMonthlyMinor, economy: economy)) per month)"
            }
        case .selfEmployment:
            let cap = rules.selfEmploymentMonthlyCap(economy: economy)
            if monthly > cap {
                return "over the self-employment cap of \(Money.format(cap, economy: economy)) per month"
            }
        }
        return nil
    }

    // MARK: Helpers

    private static func saturatingAdd(_ a: Int64, _ b: Int64) -> Int64 {
        let (r, overflow) = a.addingReportingOverflow(b)
        if !overflow { return r }
        return b > 0 ? Int64.max : Int64.min
    }
}
