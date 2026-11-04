import Testing
@testable import LifeCore

@Suite struct BankingFinanceTests {
    let date = TestChat.date
    let economy = EconomyCard.sampleUS2005

    @Test func transfersConserveCashAndUseRunningSourceBalances() throws {
        let initial = FinanceEngine.Plan(positions: [], balance: 100,
                                        accountBalances: ["personal": 100, "business": 1_000])
        let requests = [AccountTransfer(fromAccount: "business", toAccount: "personal", amountMinor: 800, reason: "Owner distribution"),
                        AccountTransfer(fromAccount: "business", toAccount: "personal", amountMinor: 300, reason: "Another distribution")]
        let result = try BankingEngine.transfer(requests, date: date, plan: initial)
        #expect(result.accountBalances == ["personal": 900, "business": 200])
        #expect(result.rejections.count == 1)
        #expect(result.ledger.count == 2)
        #expect(result.ledger.reduce(Int64(0)) { $0 + $1.amountMinor } == 0)
        #expect(result.ledger.allSatisfy { $0.sourceType == .transfer && $0.origin == .engine })
    }

    @Test func personalPurchaseCannotSpendAnUnrelatedAccountsBalance() throws {
        let initial = FinanceEngine.Plan(positions: [], balance: 0,
                                        accountBalances: ["personal": 0, "business": 1_000])
        let buy = FinancialAction(action: .buyAsset, id: "desk", name: "Desk", amountMinor: 600)
        let denied = try FinanceEngine.actions([buy], date: date, age: 30, economy: economy, streams: [], plan: initial)
        #expect(denied.positions.isEmpty && denied.ledger.isEmpty)
        #expect(denied.accountBalances == initial.accountBalances)
        #expect(denied.rejections.count == 1)

        let transferred = try BankingEngine.transfer([
            AccountTransfer(fromAccount: "business", toAccount: "personal", amountMinor: 600, reason: "Fund purchase")
        ], date: date, plan: initial)
        let bought = try FinanceEngine.actions([buy], date: date, age: 30, economy: economy, streams: [], plan: transferred)
        #expect(bought.rejections.isEmpty)
        #expect(bought.accountBalances == ["personal": 0, "business": 400])
        #expect(bought.positions.first?.principalMinor == 600)
    }

    @Test func reservedDebtIDsCannotBecomeOwnedAssetsOrInvestments() throws {
        let stream = IncomeStream(name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000, startedOn: date)
        for id in ["living-arrears", "fine-arrears", "_engine_debt"] {
            for kind in [FinancialAction.Kind.buyAsset, .invest, .borrow] {
                let result = try FinanceEngine.actions([
                    FinancialAction(action: kind, id: id, name: "Reserved position", amountMinor: 100)
                ], date: date, age: 30, economy: economy, streams: [stream],
                   plan: FinanceEngine.Plan(positions: [], balance: 10_000))
                #expect(result.positions.isEmpty && result.ledger.isEmpty)
                #expect(result.balance == 10_000)
                #expect(result.rejections.count == 1)
            }
        }
    }

    @Test func legacyReservedIDCollisionCannotConvertBillsIntoInvestmentPrincipal() throws {
        let corrupt = FinancialPosition(id: "living-arrears", name: "Old collision", kind: .investment,
                                        principalMinor: 100, openedOn: date)
        #expect(throws: ValidationError.self) {
            try FinanceEngine.settle(to: date.adding(months: 1), character: Character(from: TestChat.newCharacter()),
                streams: [], economy: economy, balance: 0, positions: [corrupt], paths: [])
        }
    }

    @Test func recurringBusinessIncomeSupportsCreditOnlyInItsDestinationAccount() throws {
        let stream = IncomeStream(name: "Website", kind: .wage, tier: "entry", monthlyMinor: 5_000_000,
                                  startedOn: date, accountId: "business")
        let initial = FinanceEngine.Plan(positions: [], balance: 0, accountBalances: ["personal": 0, "business": 0])
        let businessLoan = FinancialAction(action: .borrow, id: "hosting", name: "Hosting expansion",
                                          amountMinor: 1_000_000, accountId: "business")
        let approved = try FinanceEngine.actions([businessLoan], date: date, age: 18, economy: economy,
                                                streams: [stream], plan: initial)
        #expect(approved.rejections.isEmpty)
        #expect(approved.accountBalances == ["personal": 0, "business": 1_000_000])
        #expect(approved.positions.first?.accountId == "business")

        var personalLoan = businessLoan; personalLoan.accountId = "personal"
        let denied = try FinanceEngine.actions([personalLoan], date: date, age: 18, economy: economy,
                                              streams: [stream], plan: initial)
        #expect(denied.ledger.isEmpty && denied.positions.isEmpty)
        #expect(denied.rejections.count == 1)
    }

    @Test func endedAndFutureIncomeCannotSupportBorrowing() throws {
        let initial = FinanceEngine.Plan(positions: [], balance: 100_000)
        let borrow = FinancialAction(action: .borrow, id: "loan", name: "Loan", amountMinor: 100_000)
        var ended = IncomeStream(name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000,
                                 startedOn: date.adding(months: -1))
        ended.endedOn = date
        let future = IncomeStream(name: "Next job", kind: .wage, tier: "entry", monthlyMinor: 200_000,
                                  startedOn: date.adding(days: 1))
        let result = try FinanceEngine.actions([borrow], date: date, age: 30, economy: economy,
                                              streams: [ended, future], plan: initial)
        #expect(result.positions.isEmpty && result.ledger.isEmpty)
        #expect(result.rejections.count == 1)
    }

    @Test func onlyPreExistingWageIncomeSupportsBorrowing() throws {
        let initial = FinanceEngine.Plan(positions: [], balance: 100_000)
        let borrow = FinancialAction(action: .borrow, id: "loan", name: "Loan", amountMinor: 100_000)
        let allowance = IncomeStream(name: "Grandma", kind: .allowance, tier: nil, monthlyMinor: 200_000, startedOn: date.adding(months: -1))
        let denied = try FinanceEngine.actions([borrow], date: date, age: 30, economy: economy, streams: [allowance], plan: initial)
        #expect(denied.positions.isEmpty && denied.rejections.count == 1)
        let wage = IncomeStream(name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000, startedOn: date.adding(months: -1))
        let ok = try FinanceEngine.actions([borrow], date: date, age: 30, economy: economy, streams: [wage], plan: initial)
        #expect(ok.positions.count == 1 && ok.rejections.isEmpty)
    }

    @Test func sameTurnWageStreamCannotQualifyALoan() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        var proposed = output("You take a job and ask for a loan.", streams: [
            IncomeStreamChange(action: .start, name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000)])
        proposed.resolution.financialActions = [.init(action: .borrow, id: "loan", name: "Loan", amountMinor: 100_000)]
        let narrator = ScriptedNarrator(narrate: [.output(proposed)], repair: [.output(proposed)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        await #expect(throws: TurnError.self) { _ = try await processor.play("Take a job and borrow.") }
        #expect(try store.positions().isEmpty)
    }

    @Test func sameTurnRaiseOrRehireCannotRaiseTheCreditLimit() async throws {
        for rehire in [false, true] {
            let store = try TestChat.chat(try TestChat.library()).store
            try BankingEngine.manage(store: store, openings: [], changes: [
                IncomeStreamChange(action: .start, name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000)
            ], transfers: [], expectedRevision: store.revision())
            if rehire {
                try BankingEngine.manage(store: store, openings: [], changes: [
                    IncomeStreamChange(action: .end, name: "Shop", kind: nil, tier: nil, monthlyMinor: nil)
                ], transfers: [], expectedRevision: store.revision())
            }
            var proposed = output("You get a raise and ask for a loan.", streams: [
                IncomeStreamChange(action: rehire ? .start : .change, name: "Shop", kind: .wage, tier: "professional", monthlyMinor: 900_000)])
            proposed.resolution.financialActions = [.init(action: .borrow, id: "loan", name: "Loan", amountMinor: 2_700_000)]
            let narrator = ScriptedNarrator(narrate: [.output(proposed)], repair: [.output(proposed)])
            let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
            await #expect(throws: TurnError.self) { _ = try await processor.play("Raise, then borrow.") }
            #expect(try store.positions().isEmpty)
        }
    }

    @Test func reusedArrearsRowFollowsThePersonalAccount() throws {
        let row = FinancialPosition(id: "living-arrears", name: "Unpaid living costs", kind: .arrears, principalMinor: 0,
                                    openedOn: date, accountId: "personal")
        var plan = FinanceEngine.Plan(positions: [row], balance: 0, accountBalances: ["chk": 0], personalAccountId: "chk")
        plan = try FinanceEngine.record([FinanceEngine.entry(.livingCost, -500, "Rent", date, accountId: "chk")], to: plan)
        let arrears = try #require(plan.positions.first { $0.id == "living-arrears" })
        #expect(arrears.principalMinor == 500 && arrears.accountId == "chk")
    }

    @Test func repaidLoanRowsArePrunedSoTheStoreBoundHolds() throws {
        let wage = IncomeStream(name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 1_000_000, startedOn: date.adding(months: -1))
        var plan = FinanceEngine.Plan(positions: [], balance: 0)
        for n in 0..<250 {
            plan = try FinanceEngine.actions([.init(action: .borrow, id: "l\(n)", name: "Loan \(n)", amountMinor: 1_000)],
                                             date: date, age: 30, economy: economy, streams: [wage], plan: plan)
            plan = try FinanceEngine.actions([.init(action: .repay, id: "l\(n)", name: "Loan \(n)", amountMinor: 1_000)],
                                             date: date, age: 30, economy: economy, streams: [wage], plan: plan)
        }
        #expect(plan.rejections.isEmpty && plan.positions.count <= 50)
    }

    @Test func streamEndMustNotOutlastTheAccountClosure() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try BankingEngine.manage(store: store, openings: [.init(id: "side", name: "Side", kind: .personal)], changes: [
            IncomeStreamChange(action: .start, name: "Gig", kind: .wage, tier: "entry", monthlyMinor: 200_000, accountId: "side")
        ], transfers: [], expectedRevision: store.revision())
        let close = [AccountLifecycleChange(action: .close, accountId: "side", balanceDestinationAccountId: "personal", effectiveFrom: "2020-04-10")]
        func end(_ on: String?) -> [IncomeStreamChange] { [IncomeStreamChange(action: .end, name: "Gig", kind: nil, tier: nil, monthlyMinor: nil, effectiveFrom: on)] }
        #expect(throws: ValidationError.self) { try store.validateAccountClosures(close, incomeChanges: end(nil)) }
        #expect(throws: ValidationError.self) { try store.validateAccountClosures(close, incomeChanges: end("2020-07-01")) }
        try store.validateAccountClosures(close, incomeChanges: end("2020-04-10"))
        try store.validateAccountClosures([AccountLifecycleChange(action: .close, accountId: "side", balanceDestinationAccountId: "personal")], incomeChanges: end(nil))
    }

    @Test func closedPositionsFreeTheirIDsAndSlots() throws {
        var plan = FinanceEngine.Plan(positions: [], balance: 1_000_000)
        for n in 0..<110 {
            plan = try FinanceEngine.actions([.init(action: .buyAsset, id: "a\(n)", name: "Asset \(n)", amountMinor: 100),
                                              .init(action: .sellAsset, id: "a\(n)", name: "Asset \(n)", amountMinor: 100)],
                                             date: date, age: 30, economy: economy, streams: [], plan: plan)
        }
        #expect(plan.rejections.isEmpty)
        let again = try FinanceEngine.actions([.init(action: .buyAsset, id: "a0", name: "Asset 0", amountMinor: 100)],
                                              date: date, age: 30, economy: economy, streams: [], plan: plan)
        #expect(again.rejections.isEmpty)
        #expect(again.positions.filter { $0.id == "a0" }.count == 1 && again.positions.first { $0.id == "a0" }?.principalMinor == 100)
    }

    @Test func closedPositionRowsArePrunedSoTheStoreBoundHolds() throws {
        var plan = FinanceEngine.Plan(positions: [], balance: 1_000_000)
        for n in 0..<250 {
            plan = try FinanceEngine.actions([.init(action: .buyAsset, id: "a\(n)", name: "Asset \(n)", amountMinor: 100),
                                              .init(action: .sellAsset, id: "a\(n)", name: "Asset \(n)", amountMinor: 100)],
                                             date: date, age: 30, economy: economy, streams: [], plan: plan)
        }
        #expect(plan.rejections.isEmpty && plan.positions.count <= 50)
        #expect(plan.positions.contains { $0.id == "a249" })
    }

    @Test func taxReservesAndBusinessAccountsDoNotCountTowardTheAccountCap() {
        var existing = [BankAccount(id: "personal", name: "Personal", kind: .personal)]
        for n in 0..<19 { existing.append(BankAccount(id: "reserve\(n)", name: "Reserve \(n)", kind: .taxReserve, businessId: "b\(n)")) }
        let result = BankingEngine.open([.init(id: "rainy", name: "Rainy day", kind: .savings)], existing: existing)
        #expect(result.rejections.isEmpty && result.openings.count == 1)
        let twin = BankingEngine.open([.init(id: "personal", name: "Other", kind: .savings)], existing: existing)
        #expect(twin.openings.isEmpty)
    }

    @Test func accountIDUniquenessIsCaseInsensitive() {
        let existing = [BankAccount(id: "personal", name: "Personal", kind: .personal),
                        BankAccount(id: "Acme-Ops", name: "Acme", kind: .business)]
        let result = BankingEngine.open([.init(id: "acme-ops", name: "Twin", kind: .savings)], existing: existing)
        #expect(result.openings.isEmpty && result.rejections.count == 1)
    }

    @Test func manageFinancesIsRefusedAfterTheLifeEnds() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try store.dbQueue.write { try $0.execute(sql: "UPDATE session SET ended = 1") }
        let revision = try store.revision()
        #expect(throws: ValidationError.self) {
            try BankingEngine.manage(store: store, openings: [.init(id: "post", name: "Post", kind: .savings)], changes: [],
                                     transfers: [], expectedRevision: revision)
        }
        #expect(try store.revision() == revision && store.accounts().count == 1)
        #expect(throws: ValidationError.self) {
            try store.applyFinancialChanges(accountOpenings: [.init(id: "post", name: "Post", kind: .savings)], streamChanges: [],
                                            ledger: [], expectedRevision: revision)
        }
    }

    @Test func manageFinancesRejectsJobsForYoungChildren() throws {
        let library = try TestChat.library()
        let store = try TestChat.chat(library, age: 6).store
        let revision = try store.revision()
        #expect(throws: ValidationError.self) {
            try BankingEngine.manage(store: store, openings: [], changes: [
                IncomeStreamChange(action: .start, name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000)
            ], transfers: [], expectedRevision: revision)
        }
        #expect(try store.incomeStreams().isEmpty)
    }

    @Test func manageFinancesRejectsStreamIntoAccountWithPendingClose() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try BankingEngine.manage(store: store, openings: [.init(id: "side", name: "Side", kind: .personal)], changes: [], transfers: [], expectedRevision: store.revision())
        try store.dbQueue.write { db in
            var state = try LifeStore.simulationRecord(db, key: "business", default: BusinessSimulationState())
            state.pendingAccountChanges = [.init(action: .close, accountId: "side", balanceDestinationAccountId: "personal", effectiveFrom: "2099-01-01")]
            try LifeStore.writeSimulationRecord(db, key: "business", value: state)
        }
        #expect(throws: ValidationError.self) {
            try BankingEngine.manage(store: store, openings: [], changes: [
                IncomeStreamChange(action: .start, name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000, accountId: "side")
            ], transfers: [], expectedRevision: store.revision())
        }
        #expect(try store.incomeStreams().isEmpty)
    }

    @Test func businessIncomeDoesNotSilentlyPayPersonalBillsAndDoesNotDuplicatePathProfit() throws {
        let path = OpportunityPath(id: "website", title: "Website", stage: .profit, startedOn: date)
        let stream = IncomeStream(name: "Website subscriptions", kind: .business, tier: nil, monthlyMinor: 5_000_000,
                                  startedOn: date, accountId: "business", pathId: "website")
        let accounts = [BankAccount(id: "personal", name: "Personal", kind: .personal),
                        BankAccount(id: "business", name: "Business", kind: .business)]
        let result = try FinanceEngine.settle(to: date.adding(months: 1), character: Character(from: TestChat.newCharacter()),
            streams: [stream], economy: economy, balance: 0, positions: [], paths: [path], accounts: accounts)
        #expect(result.accountBalances == ["personal": 0, "business": 5_000_000])
        #expect(result.positions.first?.kind == .arrears)
        #expect(result.positions.first?.principalMinor == economy.monthlyLivingCostMinor)
        #expect(result.ledger.filter { $0.sourceType == .businessProfit }.count == 1)
        #expect(result.ledger.filter { $0.sourceType == .businessProfit }.first?.accountId == "business")
    }

    @Test func endingBusinessIncomeDoesNotRestoreLegacyPathProfit() throws {
        let path = OpportunityPath(id: "website", title: "Website", stage: .profit, startedOn: date)
        let stream = IncomeStream(name: "Website", kind: .business, tier: nil, monthlyMinor: 5_000_000,
                                  startedOn: date, endedOn: date.adding(months: 1), pathId: "website")
        let result = try FinanceEngine.settle(to: date.adding(months: 3), character: Character(from: TestChat.newCharacter()),
            streams: [stream], economy: economy, balance: 100, positions: [], paths: [path], household: .familySupported)
        #expect(result.balance == 100)
        #expect(result.ledger.isEmpty)
    }

    @Test func loanPaymentsAndInvestmentInterestStayInTheirRecordedAccount() throws {
        let positions = [FinancialPosition(id: "fund", name: "Fund", kind: .investment, principalMinor: 120_000,
                            annualRateBPS: 300, openedOn: date, accountId: "business"),
                         FinancialPosition(id: "loan", name: "Loan", kind: .loan, principalMinor: 10_000,
                            annualRateBPS: 0, monthlyPaymentMinor: 400, openedOn: date, accountId: "business")]
        let accounts = [BankAccount(id: "personal", name: "Personal", kind: .personal, balanceMinor: 1_000),
                        BankAccount(id: "business", name: "Business", kind: .business, balanceMinor: 100)]
        let result = try FinanceEngine.settle(to: date.adding(months: 1), character: Character(from: TestChat.newCharacter()),
            streams: [], economy: economy, balance: 1_100, positions: positions, paths: [], household: .familySupported, accounts: accounts)
        #expect(result.accountBalances == ["personal": 1_000, "business": 0])
        #expect(result.ledger.map(\.amountMinor) == [300, -400])
        #expect(result.ledger.allSatisfy { $0.accountId == "business" })
        #expect(result.positions.last?.principalMinor == 9_600)
    }

    @Test func turnCanTransferBusinessFundsAndPayOrdinaryExpense() async throws {
        let store = try fundedBusinessStore()
        var proposed = output("You transfer funds and pay the bill.", money: [
            ProposedMoneyEntry(sourceType: .expense, amountMinor: -5_000, reason: "Pay a personal bill")])
        proposed.resolution.transfers = [.init(fromAccount: "business", toAccount: "personal",
                                               amountMinor: 5_000, reason: "Owner distribution")]
        let narrator = ScriptedNarrator(narrate: [.output(proposed)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        let result = try await processor.play("Transfer fifty dollars to my personal account and pay the bill.")
        #expect(result.rejections.isEmpty && !result.repaired)
        #expect(try store.balanceMinor() == 170_000)
        #expect(try store.accounts().first { $0.id == "personal" }?.balanceMinor == 0)
        #expect(try store.accounts().first { $0.id == "business" }?.balanceMinor == 170_000)
        #expect(try store.ledger(limit: 3).filter { $0.sourceType == .expense }.count == 1)
    }

    @Test func turnCanTransferBusinessFundsAndBuyAsset() async throws {
        let store = try fundedBusinessStore()
        var proposed = output("You transfer funds and buy a desk.")
        proposed.resolution.transfers = [.init(fromAccount: "business", toAccount: "personal",
                                               amountMinor: 10_000, reason: "Owner distribution")]
        proposed.resolution.financialActions = [.init(action: .buyAsset, id: "desk", name: "Desk", amountMinor: 10_000)]
        let processor = TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(proposed)]), fate: FixedFate([50]))
        let result = try await processor.play("Transfer a hundred dollars and buy the desk.")
        #expect(result.rejections.isEmpty)
        #expect(try store.accounts().first { $0.id == "personal" }?.balanceMinor == 0)
        #expect(try store.accounts().first { $0.id == "business" }?.balanceMinor == 165_000)
        #expect(try store.positions().first?.principalMinor == 10_000)
    }

    @Test func turningEighteenAndStartingBusinessIncomeCannotSupportLoanInSameTurn() async throws {
        let store = try TestChat.chat(try TestChat.library(), age: 17).store
        var settings = SessionSettings(); settings.household = .familySupported
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        var proposed = output("At eighteen, your website earns monthly profit and qualifies for credit.",
            time: TimeAdvance(unit: .years, amount: 1), streams: [
                IncomeStreamChange(action: .start, name: "Website", kind: .business, tier: nil, monthlyMinor: 500_000,
                                   accountId: "business", reason: "Established subscriptions fund monthly net profit.")])
        proposed.resolution.accountOpenings = [.init(id: "business", name: "Business", kind: .business)]
        proposed.resolution.financialActions = [.init(action: .borrow, id: "loan", name: "Hosting credit",
                                                      amountMinor: 100_000, accountId: "business")]
        let narrator = ScriptedNarrator(narrate: [.output(proposed)], repair: [.output(proposed)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        // Docs: loans need positive wage surplus from income that already existed before the turn.
        await #expect(throws: TurnError.self) { _ = try await processor.play("Work on the website for a year, then borrow against its income when I turn eighteen.") }
        #expect(try store.positions().isEmpty)
    }

    @Test func turnCannotBorrowAgainstIncomeItEndsAndFailedTurnIsAtomic() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try BankingEngine.manage(store: store, openings: [], changes: [
            IncomeStreamChange(action: .start, name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000)
        ], transfers: [], expectedRevision: store.revision())
        let revision = try store.revision()
        let accounts = try store.accounts()
        var proposed = output("You quit and request a loan.", streams: [
            IncomeStreamChange(action: .end, name: "Shop", kind: nil, tier: nil, monthlyMinor: nil)])
        proposed.resolution.financialActions = [.init(action: .borrow, id: "loan", name: "Loan", amountMinor: 100_000)]
        let narrator = ScriptedNarrator(narrate: [.output(proposed)], repair: [.output(proposed)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        await #expect(throws: TurnError.self) { _ = try await processor.play("Quit my job and borrow against its income.") }
        #expect(try store.revision() == revision)
        #expect(try store.accounts() == accounts)
        #expect(try store.positions().isEmpty)
        #expect(try store.incomeStreams().first?.endedOn == nil)
        #expect(try store.messageCount() == 0)
    }

    private func fundedBusinessStore() throws -> LifeStore {
        let store = try TestChat.chat(try TestChat.library()).store
        try BankingEngine.manage(store: store,
            openings: [.init(id: "business", name: "Business", kind: .business)], changes: [],
            transfers: [.init(fromAccount: "personal", toAccount: "business", amountMinor: 175_000, reason: "Business reserves")],
            expectedRevision: store.revision())
        return store
    }
}
