import Testing
@testable import LifeCore

@Suite struct IncomeEngineTests {
    let start = GameDate(year: 2020, month: 1, day: 1)
    let end = GameDate(year: 2020, month: 4, day: 1)
    let economy = EconomyCard.sampleUS2005
    let accounts = [BankAccount(id: "personal", name: "Personal", kind: .personal),
                    BankAccount(id: "website", name: "Website", kind: .business)]

    private func business(_ name: String = "Website", monthly: Int64 = 5_000_000,
                          effective: String? = nil, account: String? = nil,
                          path: String? = nil, reason: String? = "Established subscriptions pay monthly.") -> IncomeStreamChange {
        IncomeStreamChange(action: .start, name: name, kind: .business, tier: nil, monthlyMinor: monthly,
                           accountId: account, pathId: path, effectiveFrom: effective, reason: reason)
    }

    private func plan(_ changes: [IncomeStreamChange], existing: [IncomeStream] = [],
                      playStyle: PlayStyle = .simulation, paths: [OpportunityPath] = []) -> IncomeEngine.Plan {
        IncomeEngine.plan(changes: changes, existing: existing, start: start, end: end,
                          economy: economy, playStyle: playStyle, accounts: accounts, paths: paths)
    }

    @Test func fiftyThousandMonthlyBusinessIsAcceptedAndRouted() {
        let result = plan([business(account: " WEBSITE ")])
        #expect(result.rejections.isEmpty)
        #expect(result.streams.count == 1)
        #expect(result.streams.first?.monthlyMinor == 5_000_000)
        #expect(result.streams.first?.accountId == "website")
        #expect(result.streams.first?.startedOn == end)
        #expect(result.changes.first?.effectiveFrom == end.iso)
    }

    @Test func rateChangeKeepsOldVersionAndChangesOnlyLaterPayments() {
        let old = IncomeStream(name: "Website", kind: .business, tier: nil, monthlyMinor: 1_000_000,
                               startedOn: start, accountId: "website")
        let raise = IncomeStreamChange(action: .change, name: "website", kind: nil, tier: nil,
            monthlyMinor: 5_000_000, effectiveFrom: "2020-03-01", reason: "Subscriber growth increased monthly profit.")
        let result = plan([raise], existing: [old])
        #expect(result.rejections.isEmpty)
        #expect(result.streams.count == 2)
        #expect(result.streams[0].monthlyMinor == 1_000_000)
        #expect(result.streams[0].endedOn?.iso == "2020-03-01")
        #expect(result.streams[1].startedOn.iso == "2020-03-01")
        #expect(result.streams[1].accountId == "website")
        #expect(result.changes[0].name == "Website")
        var character = Character(from: TestChat.newCharacter())
        character.currentDate = start
        let payroll = TimeEngine.plan(days: end.daysSince(start), character: character, streams: result.streams,
                                      economy: economy, household: .familySupported)
        #expect(payroll.map(\.amountMinor) == [1_000_000, 5_000_000, 5_000_000])
        #expect(payroll.map(\.date.iso) == ["2020-02-01", "2020-03-01", "2020-04-01"])
    }

    @Test func endingOnPaymentDateExcludesThatPayment() {
        let old = IncomeStream(name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000, startedOn: start)
        let stop = IncomeStreamChange(action: .end, name: "SHOP", kind: nil, tier: nil, monthlyMinor: nil,
                                      effectiveFrom: "2020-03-01")
        let result = plan([stop], existing: [old])
        #expect(result.rejections.isEmpty)
        var character = Character(from: TestChat.newCharacter()); character.currentDate = start
        let payroll = TimeEngine.plan(days: end.daysSince(start), character: character, streams: result.streams,
                                      economy: economy, household: .familySupported)
        #expect(payroll.map(\.amountMinor) == [200_000])
        #expect(payroll.first?.date.iso == "2020-02-01")
    }

    @Test func datesCannotRewriteSettledHistoryOrSchedulePastTurnEnd() {
        for date in ["2019-12-31", "2020-04-02", "2020-02-30", "2020-2-01", "tomorrow"] {
            let result = plan([business(effective: date)])
            #expect(result.streams.isEmpty)
            #expect(result.changes.isEmpty)
            #expect(result.rejections.count == 1)
        }
        #expect(plan([business(effective: start.iso)]).rejections.isEmpty)
        #expect(plan([business(effective: end.iso)]).rejections.isEmpty)
    }

    @Test func repeatedStreamChangesCannotOverwriteOrDoublePay() {
        let result = plan([business(" Website ", effective: start.iso),
                           business("website", effective: "2020-02-01")])
        #expect(result.streams.count == 1)
        #expect(result.changes.count == 1)
        #expect(result.rejections.count == 1)
        #expect(result.rejections[0].contains("one change"))
    }

    @Test func highBusinessRentalAndAllowanceRequireSourceRationale() {
        for kind in [IncomeStream.Kind.business, .rental, .allowance] {
            var change = business(reason: " \n "); change.kind = kind
            #expect(plan([change]).changes.isEmpty)
            change.reason = "Recorded monthly payments from the established source."
            #expect(plan([change]).rejections.isEmpty)
        }
        #expect(plan([business(monthly: economy.medianMonthlyIncomeMinor, reason: nil)]).rejections.isEmpty)
    }

    @Test func sandboxRelaxesEconomicBandsButKeepsAmountAndSourceChecks() {
        let wage = IncomeStreamChange(action: .start, name: "Dream job", kind: .wage, tier: nil, monthlyMinor: 5_000_000)
        #expect(plan([wage]).changes.isEmpty)
        #expect(plan([wage], playStyle: .sandbox).rejections.isEmpty)
        var freelance = wage; freelance.kind = .selfEmployment
        #expect(plan([freelance]).changes.isEmpty)
        #expect(plan([freelance], playStyle: .sandbox).rejections.isEmpty)
        for amount: Int64 in [0, -1, Int64.max, IncomeEngine.maximumMonthlyMinor + 1] {
            #expect(plan([business(monthly: amount)], playStyle: .sandbox).changes.isEmpty)
        }
        #expect(plan([business(reason: nil)], playStyle: .sandbox).changes.isEmpty)
    }

    @Test func unknownAccountsAndInvalidPathLinksAreRejected() {
        #expect(plan([business(account: "missing")]).changes.isEmpty)
        #expect(plan([business(path: "missing")]).changes.isEmpty)
        var path = OpportunityPath(id: "website", title: "Website", stage: .profit, startedOn: start)
        #expect(plan([business(path: "website")], paths: [path]).rejections.isEmpty)
        path.stage = .abandoned
        #expect(plan([business(path: "website")], paths: [path]).changes.isEmpty)
        var nonBusiness = business(path: "website"); nonBusiness.kind = .allowance
        #expect(plan([nonBusiness], paths: [path]).changes.isEmpty)
    }

    @Test func oneActiveStreamPerPathPreventsDuplicatedBusinessIncome() {
        let path = OpportunityPath(id: "website", title: "Website", stage: .profit, startedOn: start)
        let result = plan([business("Subscriptions", path: "website"), business("Same revenue", path: "website")], paths: [path])
        #expect(result.changes.count == 1)
        #expect(result.rejections.count == 1)
    }

    @Test func twentyStreamLimitAllowsAReplacementAtTheSameBoundary() {
        let existing = (0..<20).map {
            IncomeStream(name: "Source \($0)", kind: .business, tier: nil, monthlyMinor: 100, startedOn: start)
        }
        #expect(plan([business()], existing: existing).changes.isEmpty)
        let stop = IncomeStreamChange(action: .end, name: "Source 0", kind: nil, tier: nil, monthlyMinor: nil)
        let result = plan([business(), stop], existing: existing)
        #expect(result.rejections.isEmpty)
        #expect(result.streams.filter { $0.endedOn == nil }.count == 20)
        #expect(result.changes.first?.action == .end)
    }

    @Test func changingAwayFromBusinessClearsItsPathLink() {
        let old = IncomeStream(name: "Website", kind: .business, tier: nil, monthlyMinor: 100,
                               startedOn: start, pathId: "website")
        let change = IncomeStreamChange(action: .change, name: "Website", kind: .selfEmployment, tier: nil, monthlyMinor: 100)
        let result = plan([change], existing: [old])
        #expect(result.rejections.isEmpty)
        #expect(result.streams.last?.kind == .selfEmployment)
        #expect(result.streams.last?.pathId == nil)
    }
}
