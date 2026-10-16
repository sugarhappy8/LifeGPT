import Foundation
import Testing
@testable import LifeCore

@Suite struct FinanceAndPathTests {
    let economy = EconomyCard.sampleUS2005
    let date = TestChat.date

    @Test func missedBillsCreateRecordedDebtWithoutNegativeCash() throws {
        let character = Character(from: TestChat.newCharacter())
        let plan = try FinanceEngine.settle(to: date.adding(months: 2), character: character, streams: [],
            economy: economy, balance: 175_000, positions: [], paths: [])
        #expect(plan.balance == 0)
        #expect(plan.positions.first?.kind == .arrears)
        #expect(plan.positions.first?.principalMinor == 65_000)
        #expect(plan.ledger.filter { $0.sourceType == .livingCost }.count == 2)
        #expect(plan.ledger.reduce(Int64(175_000)) { $0 + $1.amountMinor } == plan.balance)
    }
    @Test func unownedSaleAndUnfundedPurchaseCannotCreateMoney() throws {
        let actions = [FinancialAction(action: .sellAsset, id: "car", name: "Car", amountMinor: 200_000),
                       FinancialAction(action: .buyAsset, id: "car", name: "Car", amountMinor: 200_000)]
        let plan = try FinanceEngine.actions(actions, date: date, age: 30, economy: economy, streams: [],
            plan: FinanceEngine.Plan(positions: [], balance: 100))
        #expect(plan.balance == 100); #expect(plan.ledger.isEmpty); #expect(plan.rejections.count == 2)
    }
    @Test func assetResaleAndInvestmentInterestUseEngineAmounts() throws {
        let bought = try FinanceEngine.actions([FinancialAction(action: .buyAsset, id: "bicycle", name: "Bicycle", amountMinor: 10_000)],
            date: date, age: 30, economy: economy, streams: [], plan: FinanceEngine.Plan(positions: [], balance: 100_000))
        let sold = try FinanceEngine.actions([FinancialAction(action: .sellAsset, id: "bicycle", name: "Bicycle", amountMinor: 10_000)],
            date: date, age: 30, economy: economy, streams: [], plan: bought)
        #expect(sold.balance == 98_000)
        #expect(sold.positions.first?.principalMinor == 0)
        let invested = try FinanceEngine.actions([FinancialAction(action: .invest, id: "savings", name: "Savings", amountMinor: 100_000)],
            date: date, age: 30, economy: economy, streams: [], plan: FinanceEngine.Plan(positions: [], balance: 100_000))
        let accrued = try FinanceEngine.settle(to: date.adding(months: 1), character: Character(from: TestChat.newCharacter()),
            streams: [], economy: economy, balance: invested.balance, positions: invested.positions, paths: [])
        #expect(accrued.ledger.first?.sourceType == .investment)
        #expect(accrued.ledger.first?.amountMinor == 250)
        #expect(accrued.positions.first { $0.kind == .arrears }?.principalMinor == 119_750)
    }
    @Test func loansNeedIncomeAndCannotBeStacked() throws {
        let request = FinancialAction(action: .borrow, id: "loan", name: "Loan", amountMinor: 100_000)
        let empty = FinanceEngine.Plan(positions: [], balance: 0)
        let denied = try FinanceEngine.actions([request], date: date, age: 30, economy: economy, streams: [], plan: empty)
        #expect(denied.ledger.isEmpty)
        let stream = IncomeStream(name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000, startedOn: date)
        let approved = try FinanceEngine.actions([request, FinancialAction(action: .borrow, id: "second", name: "More", amountMinor: 50_000)],
            date: date, age: 30, economy: economy, streams: [stream], plan: empty)
        #expect(approved.balance == 100_000); #expect(approved.positions.count == 1)
        #expect(approved.rejections.count == 1)
        let repaid = try FinanceEngine.actions([FinancialAction(action: .repay, id: "loan", name: "Loan", amountMinor: 100_000)],
            date: date, age: 30, economy: economy, streams: [stream], plan: approved)
        #expect(repaid.balance == 0); #expect(repaid.positions.first?.principalMinor == 0)
    }
    @Test func minorsCannotBorrowOrInvest() throws {
        let request = FinancialAction(action: .invest, id: "account", name: "Account", amountMinor: 100)
        let plan = try FinanceEngine.actions([request], date: date, age: 10, economy: economy, streams: [], plan: FinanceEngine.Plan(positions: [], balance: 1000))
        #expect(plan.positions.isEmpty); #expect(plan.balance == 1000)
    }
    @Test func pathsNeedTimeCapitalAndSequentialProgress() {
        let idea = OpportunityPath(id: "shop", title: "Shop", startedOn: date)
        let early = PathEngine.plan([PathUpdate(id: "shop", title: "Shop", stage: .capital)], existing: [idea], date: date,
            age: 30, economy: economy, balance: 1_000_000, fate: 80)
        #expect(early.paths.first?.stage == .idea)
        let capital = PathEngine.plan([PathUpdate(id: "shop", title: "Shop", stage: .capital)], existing: [idea], date: date.adding(days: 7),
            age: 30, economy: economy, balance: 1_000_000, fate: 80)
        #expect(capital.paths.first?.investedMinor == 175_000)
        #expect(capital.ledger.first?.amountMinor == -175_000)
        let jump = PathEngine.plan([PathUpdate(id: "shop", title: "Shop", stage: .profit)], existing: capital.paths, date: date.adding(days: 1000),
            age: 30, economy: economy, balance: 1_000_000, fate: 80)
        #expect(jump.paths.first?.stage == .capital)
        let launch = PathEngine.plan([PathUpdate(id: "shop", title: "Shop", stage: .launch)], existing: capital.paths, date: date.adding(days: 37),
            age: 30, economy: economy, balance: 1_000_000, fate: 80)
        #expect(launch.paths.first?.stage == .launch)
    }
    @Test func repeatedPathChangesCannotSkipStagesInOneTurn() {
        let changes = [PathUpdate(id: "shop", title: "Shop", stage: .idea), PathUpdate(id: "shop", title: "Shop", stage: .capital)]
        let plan = PathEngine.plan(changes, existing: [], date: date, age: 30, economy: economy, balance: 1_000_000, fate: 99)
        #expect(plan.paths.count == 1); #expect(plan.paths.first?.stage == .idea); #expect(plan.rejections.count == 1)
    }

    @Test func narratedCapitalUsesReplacementPersonalAccount() async throws {
        let library = try TestChat.library()
        let (_, store) = try TestChat.chat(library)
        var settings = SessionSettings()
        settings.household = .familySupported
        settings.contextLookupMode = .off
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        try BankingEngine.manage(store: store, openings: [.init(id: "replacement", name: "New personal", kind: .personal)],
            changes: [], transfers: [], expectedRevision: store.revision())
        try store.updateBusinessSimulation(accountChanges: [.init(action: .close, accountId: "personal",
            balanceDestinationAccountId: "replacement", replacementAccountId: "replacement")],
            expectedRevision: store.revision())
        let before = try store.accounts().first { $0.id == "replacement" }!.balanceMinor
        let idea = TurnOutput(resolution: .init(zoom: .scene, timeAdvance: .init(unit: .days, amount: 0),
            pathUpdates: [.init(id: "shop", title: "Shop", stage: .idea)]), narration: "You plan a shop.")
        let capital = TurnOutput(resolution: .init(zoom: .summary, timeAdvance: .init(unit: .days, amount: 7),
            pathUpdates: [.init(id: "shop", title: "Shop", stage: .capital)]), narration: "You invest your savings.")
        let narrator = ScriptedNarrator(narrate: [.output(idea), .output(capital)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([80]))
        _ = try await processor.play("Plan my shop.")
        _ = try await processor.play("After seven days, fund the shop from my default personal account.")
        let entries = try store.ledger(limit: 100).filter { $0.reason.hasPrefix("Business capital:") }
        let amount = economy.medianMonthlyIncomeMinor / 2
        #expect(entries.count == 1 && entries.first?.accountId == "replacement")
        #expect(entries.first?.amountMinor == -amount)
        #expect(try store.accounts().first { $0.id == "replacement" }?.balanceMinor == before - amount)
        #expect(try store.accounts().first { $0.id == "personal" }?.status == .closed)
        #expect(try store.paths().first?.stage == .capital && narrator.repairCalls == 0)
    }
}

@Suite struct CrimeTests {
    @Test func missingAndEmptyAttemptsHaveNoEffectsEvenForChildrenOrDuringCooldown() {
        for attempt in [nil, CrimeAttempt(reason: ""), CrimeAttempt(reason: " \n\t ")] {
            for age in [12, 18] {
                let outcome = CrimeEngine.resolve(attempt, age: age, date: TestChat.date, fate: 100,
                    economy: .sampleUS2005, lastAttempt: TestChat.date)
                #expect(outcome.rejection == nil && outcome.money == 0 && outcome.state.isEmpty && outcome.event == nil)
            }
        }
    }
    @Test func realAttemptsExplainTheFailingRule() {
        let tooLong = CrimeEngine.resolve(CrimeAttempt(reason: String(repeating: "x", count: 501)), age: 18,
            date: TestChat.date, fate: 75, economy: .sampleUS2005, lastAttempt: nil)
        #expect(tooLong.rejection?.contains("500 characters") == true)
        #expect(tooLong.rejection?.contains("age") == false)
        let underage = CrimeEngine.resolve(CrimeAttempt(reason: "An impulsive offense"), age: 15,
            date: TestChat.date, fate: 75, economy: .sampleUS2005, lastAttempt: nil)
        #expect(underage.rejection == "Crime outcomes require age 16 or older.")
        let boundary = CrimeEngine.resolve(CrimeAttempt(reason: String(repeating: "x", count: 500)), age: 16,
            date: TestChat.date, fate: 75, economy: .sampleUS2005, lastAttempt: TestChat.date.adding(days: -30))
        #expect(boundary.rejection == nil && boundary.money == 87_500)
    }
    @Test func fateChoosesFixedProceedsOrAFineAndCooldownIsBinding() throws {
        let economy = EconomyCard.sampleUS2005
        let attempt = CrimeAttempt(reason: "An impulsive offense")
        let good = CrimeEngine.resolve(attempt, age: 30, date: TestChat.date, fate: 75, economy: economy, lastAttempt: nil)
        #expect(good.money == 87_500)
        let bad = CrimeEngine.resolve(attempt, age: 30, date: TestChat.date, fate: 74, economy: economy, lastAttempt: nil)
        #expect(bad.money == -35_000)
        let settled = try FinanceEngine.applyCrime(bad, date: TestChat.date, to: FinanceEngine.Plan(positions: [], balance: 100))
        #expect(settled.balance == 0)
        #expect(settled.positions.first?.principalMinor == 34_900)
        #expect(settled.positions.first?.id == "fine-arrears")
        let blocked = CrimeEngine.resolve(attempt, age: 30, date: TestChat.date, fate: 100, economy: economy, lastAttempt: TestChat.date)
        #expect(blocked.money == 0); #expect(blocked.rejection != nil)
    }
}
