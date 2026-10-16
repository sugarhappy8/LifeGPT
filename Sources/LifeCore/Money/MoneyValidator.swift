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
    /// Days since the last gift or inheritance from anyone; nil means never.
    public var daysSinceLastAnyGift: Int?
    public var recentSideHustleMinor: Int64 = 0
    public var giverTiers: [String: WealthTier] = [:]
    public var giverStatuses: [String: String] = [:]
    public var rules: MoneyRules
    public var playStyle: PlayStyle = .simulation
    public var accountBalances: [String: Int64]? = nil

    public init(economy: EconomyCard, familyTier: WealthTier, balanceMinor: Int64, elapsedDays: Int,
                fate: Int, castNames: Set<String>, daysSinceLastWindfall: Int? = nil,
                daysSinceLastGiftByGiver: [String: Int] = [:], daysSinceLastAnyGift: Int? = nil,
                rules: MoneyRules = .v1) {
        self.economy = economy
        self.familyTier = familyTier
        self.balanceMinor = balanceMinor
        self.elapsedDays = elapsedDays
        self.fate = fate
        self.castNames = castNames
        self.daysSinceLastWindfall = daysSinceLastWindfall
        self.daysSinceLastGiftByGiver = daysSinceLastGiftByGiver
        self.daysSinceLastAnyGift = daysSinceLastAnyGift
        self.rules = rules
    }
}

public enum MoneyVerdict: Equatable, Sendable {
    case accepted
    case rejected(String)
}

/// Pure checks on structured proposals under the selected play style.
/// Only validated records can be written to the ledger.
public enum MoneyValidator {
    // MARK: Money entries

    /// One verdict per entry, in order. A running balance and the per-turn
    /// windfall and gift limits carry across entries.
    public static func validate(_ entries: [ProposedMoneyEntry], in ctx: MoneyContext) -> [MoneyVerdict] {
        var state = TurnState(balances: ctx.accountBalances ?? ["personal": ctx.balanceMinor])
        return entries.map { entry in
            let verdict = check(entry, ctx: ctx, state: state)
            if verdict == .accepted {
                let account = entry.accountId ?? "personal"
                state.balances[account] = saturatingAdd(state.balances[account, default: 0], entry.amountMinor)
                switch entry.sourceType {
                case .windfall:
                    state.windfallUsed = true
                    state.gainsTotal = saturatingAdd(state.gainsTotal, entry.amountMinor)
                case .gift, .inheritance:
                    state.giftUsed = true
                    state.gainsTotal = saturatingAdd(state.gainsTotal, entry.amountMinor)
                case .sideHustle:
                    state.sideHustleUsed = saturatingAdd(state.sideHustleUsed, entry.amountMinor)
                    state.gainsTotal = saturatingAdd(state.gainsTotal, entry.amountMinor)
                default:
                    break
                }
            }
            return verdict
        }
    }

    /// What earlier entries in the same turn have already used up, so a claim
    /// cannot be split into many small entries to get past a per-entry limit.
    private struct TurnState {
        var balances: [String: Int64]
        var windfallUsed = false
        var giftUsed = false
        var sideHustleUsed: Int64 = 0
        var gainsTotal: Int64 = 0
    }

    private static func check(_ e: ProposedMoneyEntry, ctx: MoneyContext, state: TurnState) -> MoneyVerdict {
        let economy = ctx.economy, rules = ctx.rules
        let account = e.accountId ?? "personal"
        guard let balance = state.balances[account] else { return .rejected("unknown account: \(account)") }

        if e.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .rejected("a concrete reason is required") }
        if e.amountMinor == 0 { return .rejected("zero amount") }

        switch e.sourceType {
        case .sideHustle, .gift, .inheritance, .windfall:
            if e.amountMinor < 0 { return .rejected("wrong sign: \(e.sourceType.rawValue) must be positive") }
        case .expense:
            if e.amountMinor > 0 { return .rejected("wrong sign: an expense must be negative") }
        default:
            break
        }

        let bound: Int64 = ctx.playStyle == .sandbox || e.sourceType == .expense ? 1_000_000_000_000 : rules.singleEntryBound(economy: economy)
        if e.amountMinor.magnitude > UInt64(bound) {
            return .rejected("exceeds the plausible bound for a single entry (\(Money.format(bound, economy: economy)))")
        }

        let isGain = [SourceType.sideHustle, .gift, .inheritance, .windfall].contains(e.sourceType)
        if isGain, saturatingAdd(state.gainsTotal, e.amountMinor) > bound {
            return .rejected("exceeds the plausible bound for one turn's total gains (\(Money.format(bound, economy: economy)))")
        }

        switch e.sourceType {
        case .opening, .wage, .investment, .livingCost, .transfer, .rentalIncome, .allowance:
            return .rejected("engine-only source: \(e.sourceType.rawValue) is paid or charged by the game, not proposed by the narrator")

        case .businessProfit, .assetSale, .loan, .crime:
            return .rejected("engine-only source: use a validated path, financial action, or crime attempt for \(e.sourceType.rawValue)")

        case .sideHustle:
            if ctx.playStyle == .sandbox { break }
            let cap = max(0, rules.sideHustleCap(economy: economy, elapsedDays: ctx.elapsedDays) - ctx.recentSideHustleMinor)
            if saturatingAdd(state.sideHustleUsed, e.amountMinor) > cap {
                return .rejected("over the side-hustle cap of \(Money.format(cap, economy: economy)) for this period "
                                 + "(\(Money.format(state.sideHustleUsed, economy: economy)) already used this turn)")
            }

        case .gift, .inheritance:
            guard let giver = e.counterparty,
                  ctx.castNames.contains(where: { $0.caseInsensitiveCompare(giver) == .orderedSame })
            else { return .rejected("the giver must be someone in your cast") }
            let status = ctx.giverStatuses.first { $0.key.caseInsensitiveCompare(giver) == .orderedSame }?.value
            if e.sourceType == .gift, status == "dead" { return .rejected("a dead person cannot give a new gift") }
            if e.sourceType == .inheritance, let status, status != "dead" { return .rejected("inheritance needs a recorded death") }
            if ctx.playStyle == .sandbox { break }
            let tier = ctx.giverTiers.first { $0.key.caseInsensitiveCompare(giver) == .orderedSame }?.value ?? ctx.familyTier
            let cap = rules.giftCap(economy: economy, familyTier: tier)
            if e.amountMinor > cap {
                return .rejected("over the gift cap of \(Money.format(cap, economy: economy)) for this family")
            }
            if state.giftUsed { return .rejected("gap: only one gift or inheritance per turn") }
            if let days = ctx.daysSinceLastAnyGift, days < rules.giftMinGapDays {
                return .rejected("gap: the last gift from anyone was \(days) days ago (minimum \(rules.giftMinGapDays))")
            }
            if let days = ctx.daysSinceLastGiftByGiver.first(where: { $0.key.caseInsensitiveCompare(giver) == .orderedSame })?.value,
               days < rules.giftMinGapDays {
                return .rejected("gap: the last gift from \(giver) was \(days) days ago (minimum \(rules.giftMinGapDays))")
            }

        case .windfall:
            if ctx.playStyle == .sandbox { break }
            if ctx.fate < rules.windfallMinFate {
                return .rejected("fate roll \(ctx.fate) is below the \(rules.windfallMinFate) a windfall needs")
            }
            let cap = rules.windfallCap(economy: economy)
            if e.amountMinor > cap {
                return .rejected("over the windfall cap of \(Money.format(cap, economy: economy))")
            }
            if state.windfallUsed { return .rejected("gap: only one windfall per turn") }
            if let days = ctx.daysSinceLastWindfall, days < rules.windfallMinGapDays {
                return .rejected("gap: the last windfall was \(days) days ago (minimum \(rules.windfallMinGapDays))")
            }

        case .expense:
            if saturatingAdd(balance, e.amountMinor) < 0 {
                return .rejected("account \(account) balance of \(Money.format(balance, economy: economy)) cannot cover this expense")
            }
        case .adjustment:
            guard ctx.playStyle == .sandbox else { return .rejected("record adjustments require Sandbox play style") }
            if saturatingAdd(balance, e.amountMinor) < 0 { return .rejected("an adjustment cannot make an account negative") }
        }
        return .accepted
    }

    // MARK: Income streams

    /// Shares recurring-income limits with the dated settlement planner.
    public static func validate(_ changes: [IncomeStreamChange], existing: [IncomeStream],
                                economy: EconomyCard, rules: MoneyRules,
                                playStyle: PlayStyle = .simulation) -> [MoneyVerdict] {
        IncomeEngine.validate(changes, existing: existing, economy: economy, rules: rules, playStyle: playStyle)
    }

    // MARK: Helpers

    private static func saturatingAdd(_ a: Int64, _ b: Int64) -> Int64 {
        let (r, overflow) = a.addingReportingOverflow(b)
        if !overflow { return r }
        return b > 0 ? Int64.max : Int64.min
    }
}
