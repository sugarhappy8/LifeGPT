import Testing
@testable import LifeCore

extension MoneyContext {
    static func stub(tier: WealthTier = .middle, balanceMinor: Int64 = 100_000, elapsedDays: Int = 30,
                     fate: Int = 50, cast: Set<String> = ["Maria"], daysSinceLastWindfall: Int? = nil,
                     daysSinceLastGiftByGiver: [String: Int] = [:]) -> MoneyContext {
        MoneyContext(economy: .sampleUS2005, familyTier: tier, balanceMinor: balanceMinor,
                     elapsedDays: elapsedDays, fate: fate, castNames: cast,
                     daysSinceLastWindfall: daysSinceLastWindfall,
                     daysSinceLastGiftByGiver: daysSinceLastGiftByGiver)
    }
}

private func entry(_ source: SourceType, _ amount: Int64, from giver: String? = nil) -> ProposedMoneyEntry {
    ProposedMoneyEntry(sourceType: source, amountMinor: amount, reason: "test", counterparty: giver)
}

private func reason(_ v: MoneyVerdict) -> String? {
    if case .rejected(let r) = v { return r }
    return nil
}

private func one(_ e: ProposedMoneyEntry, _ ctx: MoneyContext = .stub()) -> MoneyVerdict {
    MoneyValidator.validate([e], in: ctx)[0]
}

@Suite struct MoneyValidatorTests {
    @Test func spoonClaimOf200MillionIsRejected() {
        let v = one(entry(.sideHustle, 20_000_000_000))
        #expect(reason(v)?.contains("bound") == true)
    }

    @Test func sideHustleCapBoundary() {
        #expect(one(entry(.sideHustle, 175_000)) == .accepted)
        #expect(reason(one(entry(.sideHustle, 175_001)))?.contains("cap") == true)
    }

    @Test func shortWindowUsesSevenDayFloor() {
        let ctx = MoneyContext.stub(elapsedDays: 0)
        #expect(one(entry(.sideHustle, 40_833), ctx) == .accepted)
        #expect(reason(one(entry(.sideHustle, 40_834), ctx))?.contains("cap") == true)
    }

    @Test func engineOnlySourcesAreRejected() {
        for s in [SourceType.wage, .investment, .livingCost, .opening] {
            #expect(reason(one(entry(s, 100)))?.contains("engine-only") == true, "\(s)")
        }
    }

    @Test func notYetAvailableSourcesAreRejected() {
        for s in [SourceType.businessProfit, .assetSale, .loan, .crime] {
            #expect(reason(one(entry(s, 100)))?.contains("not available yet") == true, "\(s)")
        }
    }

    @Test func giftNeedsCastMember() {
        #expect(reason(one(entry(.gift, 1_000, from: "Bob")))?.contains("cast") == true)
        #expect(reason(one(entry(.gift, 1_000)))?.contains("cast") == true)
        #expect(one(entry(.gift, 1_000, from: "maria")) == .accepted)
    }

    @Test func giftCapFollowsFamilyWealthTier() {
        #expect(one(entry(.gift, 350_000, from: "Maria")) == .accepted)
        #expect(reason(one(entry(.gift, 350_001, from: "Maria")))?.contains("cap") == true)
        let poor = MoneyContext.stub(tier: .poor)
        #expect(one(entry(.gift, 87_500, from: "Maria"), poor) == .accepted)
        #expect(reason(one(entry(.gift, 87_501, from: "Maria"), poor))?.contains("cap") == true)
    }

    @Test func giftIsRateLimitedPerGiver() {
        let recent = MoneyContext.stub(daysSinceLastGiftByGiver: ["Maria": 30])
        #expect(reason(one(entry(.gift, 1_000, from: "Maria"), recent))?.contains("gap") == true)
        let enough = MoneyContext.stub(daysSinceLastGiftByGiver: ["Maria": 90])
        #expect(one(entry(.inheritance, 1_000, from: "Maria"), enough) == .accepted)
        let twice = MoneyValidator.validate([entry(.gift, 1_000, from: "Maria"), entry(.gift, 1_000, from: "MARIA")],
                                            in: .stub())
        #expect(twice[0] == .accepted); #expect(reason(twice[1])?.contains("gap") == true)
    }

    @Test func windfallRules() {
        #expect(reason(one(entry(.windfall, 100_000), .stub(fate: 94)))?.contains("fate") == true)
        #expect(one(entry(.windfall, 2_100_000), .stub(fate: 95)) == .accepted)
        #expect(reason(one(entry(.windfall, 2_100_001), .stub(fate: 95)))?.contains("cap") == true)
        #expect(reason(one(entry(.windfall, 100_000), .stub(fate: 99, daysSinceLastWindfall: 100)))?.contains("gap") == true)
        #expect(one(entry(.windfall, 100_000), .stub(fate: 99, daysSinceLastWindfall: 730)) == .accepted)
        let two = MoneyValidator.validate([entry(.windfall, 1_000), entry(.windfall, 1_000)], in: .stub(fate: 99))
        #expect(two[0] == .accepted); #expect(reason(two[1])?.contains("gap") == true)
    }

    @Test func expenseCannotGoNegative() {
        #expect(reason(one(entry(.expense, -100_001)))?.contains("balance") == true)
        #expect(one(entry(.expense, -100_000)) == .accepted)
        let seq = MoneyValidator.validate([entry(.expense, -60_000), entry(.expense, -60_000)], in: .stub())
        #expect(seq[0] == .accepted); #expect(reason(seq[1])?.contains("balance") == true)
    }

    @Test func earlierAcceptedGainsCountForLaterExpenses() {
        let seq = MoneyValidator.validate([entry(.sideHustle, 50_000), entry(.expense, -140_000)], in: .stub())
        #expect(seq == [.accepted, .accepted])
    }

    @Test func extremeAmountsRejectedWithoutOverflow() {
        #expect(reason(one(entry(.sideHustle, 0)))?.contains("zero") == true)
        #expect(reason(one(entry(.sideHustle, Int64.max)))?.contains("bound") == true)
        #expect(reason(one(entry(.expense, Int64.min)))?.contains("bound") == true)
        #expect(reason(one(entry(.sideHustle, -500)))?.contains("sign") == true)
        #expect(reason(one(entry(.gift, -500, from: "Maria")))?.contains("sign") == true)
        #expect(reason(one(entry(.expense, 500)))?.contains("sign") == true)
    }

    @Test func singleEntryBoundIs12TimesMedian() {
        #expect(reason(one(entry(.expense, -4_200_001), .stub(balanceMinor: 9_000_000)))?.contains("bound") == true)
    }

    // MARK: aggregate limits (final-review findings)

    @Test func splittingASideHustleCannotBeatTheCap() {
        let two = MoneyValidator.validate([entry(.sideHustle, 100_000), entry(.sideHustle, 100_000)], in: .stub())
        #expect(two[0] == .accepted); #expect(reason(two[1])?.contains("cap") == true)
        let fifty = MoneyValidator.validate(Array(repeating: entry(.sideHustle, 40_000), count: 50),
                                            in: .stub(elapsedDays: 0))
        #expect(fifty.filter { $0 == .accepted }.count == 1)
    }

    @Test func gainsInOneTurnAreBoundedInTotal() {
        let rich = MoneyContext.stub(tier: .ultraWealthy, fate: 99)
        #expect(one(entry(.windfall, 2_100_000), rich) == .accepted)
        #expect(one(entry(.gift, 2_800_000, from: "Maria"), rich) == .accepted)
        let both = MoneyValidator.validate([entry(.windfall, 2_100_000), entry(.gift, 2_800_000, from: "Maria")], in: rich)
        #expect(both[0] == .accepted); #expect(reason(both[1])?.contains("bound") == true)
    }

    @Test func onlyOneGiftPerTurnAcrossGivers() {
        let ctx = MoneyContext.stub(cast: ["Maria", "Tomás"])
        let r = MoneyValidator.validate([entry(.gift, 1_000, from: "Maria"), entry(.inheritance, 1_000, from: "Tomás")], in: ctx)
        #expect(r[0] == .accepted); #expect(reason(r[1])?.contains("gap") == true)
    }

    @Test func giftGapAppliesAcrossAllGivers() {
        var ctx = MoneyContext.stub(cast: ["Maria", "Tomás"])
        ctx.daysSinceLastAnyGift = 30
        #expect(reason(one(entry(.gift, 1_000, from: "Tomás"), ctx))?.contains("gap") == true)
        ctx.daysSinceLastAnyGift = 90
        #expect(one(entry(.gift, 1_000, from: "Tomás"), ctx) == .accepted)
    }

    // MARK: income stream changes

    private let skilled = IncomeStreamChange(action: .start, name: "shop", kind: .wage, tier: "skilled", monthlyMinor: 300_000)
    private let jan1 = GameDate(year: 2020, month: 1, day: 1)

    private func check(_ changes: [IncomeStreamChange], existing: [IncomeStream] = []) -> [MoneyVerdict] {
        MoneyValidator.validate(changes, existing: existing, economy: .sampleUS2005, rules: .v1)
    }

    @Test func wageStartMustFitItsTierBand() {
        #expect(check([skilled]) == [.accepted])
        var high = skilled; high.monthlyMinor = 600_000
        #expect(reason(check([high])[0])?.contains("band") == true)
        var unknown = skilled; unknown.tier = "wizard"
        #expect(reason(check([unknown])[0])?.contains("band") == true)
        var noTier = skilled; noTier.tier = nil
        #expect(reason(check([noTier])[0])?.contains("band") == true)
    }

    @Test func selfEmploymentIsCappedAtHalfTheMedian() {
        let ok = IncomeStreamChange(action: .start, name: "stall", kind: .selfEmployment, tier: nil, monthlyMinor: 175_000)
        var over = ok; over.monthlyMinor = 175_001
        #expect(check([ok]) == [.accepted])
        #expect(reason(check([over])[0])?.contains("cap") == true)
    }

    @Test func changeAndEndNeedAnActiveStream() {
        let active = IncomeStream(name: "shop", kind: .wage, tier: "entry", monthlyMinor: 200_000, startedOn: jan1)
        var ended = active; ended.endedOn = GameDate(year: 2020, month: 6, day: 1)
        let raise = IncomeStreamChange(action: .change, name: "Shop", kind: nil, tier: "skilled", monthlyMinor: 300_000)
        let tooMuch = IncomeStreamChange(action: .change, name: "shop", kind: nil, tier: nil, monthlyMinor: 999_999)
        let quit = IncomeStreamChange(action: .end, name: "shop", kind: nil, tier: nil, monthlyMinor: nil)
        #expect(check([raise], existing: [active]) == [.accepted])
        #expect(reason(check([tooMuch], existing: [active])[0])?.contains("band") == true)
        #expect(check([quit], existing: [active]) == [.accepted])
        #expect(reason(check([raise])[0])?.contains("unknown stream") == true)
        #expect(reason(check([quit], existing: [ended])[0])?.contains("unknown stream") == true)
    }

    @Test func startingAnAlreadyActiveStreamIsRejected() {
        let active = IncomeStream(name: "shop", kind: .wage, tier: "entry", monthlyMinor: 200_000, startedOn: jan1)
        #expect(reason(check([skilled], existing: [active])[0])?.contains("already active") == true)
    }

    @Test func changesInOneBatchSeeEachOther() {
        let raise = IncomeStreamChange(action: .change, name: "shop", kind: nil, tier: nil, monthlyMinor: 310_000)
        let quit = IncomeStreamChange(action: .end, name: "shop", kind: nil, tier: nil, monthlyMinor: nil)
        #expect(check([skilled, raise, quit]) == [.accepted, .accepted, .accepted])
        #expect(reason(check([skilled, quit, raise])[2])?.contains("unknown stream") == true)
    }
}
