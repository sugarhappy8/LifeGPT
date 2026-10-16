import Foundation
import GRDB
import Testing
@testable import LifeCore

@Suite struct SimulationIntegrationTests {
    private let texas = JurisdictionRef(countryID: "US", subdivisionID: "US-TX")
    private let start = GameDate(year: 2004, month: 1, day: 1)

    private func chat() throws -> (library: ChatLibrary, id: UUID, store: LifeStore) {
        let library = try TestChat.library()
        var character = TestChat.newCharacter(name: "Company fixture", age: 30, birthYear: 1974)
        character.birthplace = "Texas, United States"
        character.birthJurisdiction = texas; character.startingJurisdiction = texas
        let (id, store) = try library.createChat(character: character, economy: .sampleUS2005)
        var settings = SessionSettings(); settings.playStyle = .sandbox; settings.household = .familySupported
        settings.contextLookupMode = .off
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        return (library, id, store)
    }

    private func company(on date: GameDate, includeEmployees: Bool = false) -> TurnOutput {
        var proposed = output("You record the website's business agreements.")
        proposed.resolution.businessChanges = [.init(action: .create, id: "website", name: "Website", accountId: "website",
            jurisdiction: texas, legalStructure: .incorporated, effectiveFrom: date.iso)]
        proposed.resolution.obligationChanges = [
            .init(action: .start, id: "website_revenue", businessId: "website", kind: .revenue, name: "Website gross revenue",
                  monthlyMinor: 5_000_000, fromAccountId: "website", effectiveFrom: date.iso),
            .init(action: .start, id: "owner_salary", businessId: "website", kind: .ownerSalary, name: "Owner gross salary",
                  monthlyMinor: 150_000, fromAccountId: "website", toAccountId: "personal", jurisdiction: texas,
                  taxResidence: texas, effectiveFrom: date.iso)]
        if includeEmployees {
            proposed.resolution.obligationChanges?.append(.init(action: .start, id: "developers", businessId: "website", kind: .payroll,
                name: "Developers", monthlyMinor: 400_000, headcount: 2, fromAccountId: "website", jurisdiction: texas,
                taxResidence: texas, employeeBirthDate: "1975-01-01", monthlyHours: 160, effectiveFrom: date.iso))
        }
        return proposed
    }

    @Test func grossRevenuePaysStaffAndOwnerExactlyOnceAndPersists() async throws {
        let (library, id, store) = try chat()
        let initial = try store.balanceMinor()
        let setup = company(on: start, includeEmployees: true)
        let skip = output("January's accounts settle.", time: .init(unit: .months, amount: 1))
        let narrator = ScriptedNarrator(narrate: [.output(setup), .output(skip), .output(output("You check the completed payments."))])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        _ = try await processor.play("Record gross revenue and salaries.")
        #expect(try store.balanceMinor() == initial)
        #expect(try store.businessSimulation().payments.isEmpty)
        #expect(try store.incomeStreams().isEmpty)
        _ = try await processor.play("Skip one month.", skipTime: .init(unit: .months, amount: 1))
        let state = try store.businessSimulation()
        let assessment = try #require(state.assessments.first)
        #expect(state.assessments.count == 1 && assessment.revenueMinor == 5_000_000)
        #expect(assessment.grossPayrollMinor == 950_000)
        let ownerPayable = try #require(state.payables.first { $0.kind == .ownerSalary })
        let ownerPayments = state.payments.filter { $0.payableId == ownerPayable.id }
        let ownerPayment = try #require(ownerPayments.first)
        #expect(ownerPayments.count == 1 && ownerPayment.grossMinor == 150_000)
        #expect(ownerPayment.netMinor + ownerPayment.withheldMinor == 150_000)
        #expect(ownerPayment.netMinor > 0 && ownerPayment.netMinor < 150_000)
        let accounts = try store.accounts()
        #expect(accounts.first { $0.id == "personal" }?.balanceMinor == initial + ownerPayment.netMinor)
        #expect(state.payables.first { $0.kind == .payroll }?.paidMinor == 800_000)
        #expect(try store.ledger(limit: 100).filter { $0.reason.hasPrefix("Gross revenue:") }.map(\.amountMinor) == [5_000_000])
        #expect(try store.incomeStreams().isEmpty)
        let ledger = try store.ledger(limit: 100)
        _ = try await processor.play("Check the same month's completed payments without advancing time.")
        #expect(try store.businessSimulation().payments == state.payments)
        #expect(try store.ledger(limit: 100) == ledger)
        let reopened = try library.openChat(id: id)
        #expect(try reopened.businessSimulation() == store.businessSimulation())
        #expect(try reopened.accounts() == store.accounts())
    }

    @Test(arguments: [false, true])
    func invalidTurnOrRepairNetworkFailureRollsBackAllBusinessState(_ repairNetworkFailure: Bool) async throws {
        let (_, _, store) = try chat()
        let before = try store.businessSimulation(), accounts = try store.accounts(), ledger = try store.ledger(limit: 100)
        let revision = try store.revision(), date = try store.character().currentDate
        var proposed = company(on: start, includeEmployees: true)
        proposed.resolution.timeAdvance = .init(unit: .months, amount: 1)
        proposed.resolution.lifeStateChanges = [.init(key: "balance", value: "unlimited")]
        proposed.resolution.castUpdates = [.init(name: "New employee", relation: "employee", notes: nil, status: "alive")]
        proposed.authorNotes = "This must never be committed."
        let narrator = ScriptedNarrator(narrate: [.output(proposed)], repair: repairNetworkFailure ? [.error(ProviderError.badResponse)] : [.output(proposed)])
        await #expect(throws: TurnError.self) {
            _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50])).play("Configure and run the company for a month.")
        }
        #expect(narrator.repairCalls == 1)
        #expect(try store.businessSimulation() == before)
        #expect(try store.accounts() == accounts && store.ledger(limit: 100) == ledger)
        #expect(try store.revision() == revision && store.character().currentDate == date)
        #expect(try store.recentMessages(limit: 20).isEmpty && store.castMembers().isEmpty && store.positions().isEmpty)
        #expect(try store.authorNotes().isEmpty)
    }

    @Test func manualLegacyConversionIsExplicitAndNeverBackfillsHistory() async throws {
        let (_, _, store) = try chat()
        try BankingEngine.manage(store: store, openings: [.init(id: "website", name: "Website", kind: .business)], changes: [
            .init(action: .start, name: "Website net profit", kind: .business, tier: nil, monthlyMinor: 5_000_000,
                  accountId: "website", effectiveFrom: start.iso, reason: "Existing net-profit accounting")],
            transfers: [], expectedRevision: store.revision())
        let skip = output("A month passes.", time: .init(unit: .months, amount: 1))
        _ = try await TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(skip)]), fate: FixedFate([50]))
            .play("Continue for one month.")
        let date = try store.character().currentDate
        let existing = try store.ledger(limit: 100), messages = try store.recentMessages(limit: 100), revision = try store.revision()
        let proposal = company(on: date)
        #expect(throws: ValidationError.self) {
            try store.updateBusinessSimulation(businessChanges: proposal.resolution.businessChanges!,
                obligationChanges: proposal.resolution.obligationChanges!, expectedRevision: revision)
        }
        #expect(try store.revision() == revision)
        try store.updateBusinessSimulation(businessChanges: proposal.resolution.businessChanges!,
            obligationChanges: proposal.resolution.obligationChanges!, convertLegacyIncome: true, expectedRevision: revision)
        #expect(try store.incomeStreams().first?.endedOn == date)
        #expect(try store.ledger(limit: 100) == existing && store.recentMessages(limit: 100) == messages)
        #expect(try store.businessSimulation().assessments.isEmpty && store.businessSimulation().payments.isEmpty)
        #expect(try store.accounts().first { $0.id == "website" }?.balanceMinor == 5_000_000)
        _ = try await TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(skip)]), fate: FixedFate([50]))
            .play("Continue for the next month.")
        #expect(try store.ledger(limit: 100).filter { $0.sourceType == .businessProfit }.count == 2)
        #expect(try store.businessSimulation().assessments.count == 1)
    }

    @Test func confirmedSaleRevokesAllSpendingPathsAndPaysProceedsOnlyOnce() async throws {
        let (_, _, store) = try chat()
        let setup = company(on: start)
        let processor = TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(setup),
            .output(output("One month passes.", time: .init(unit: .months, amount: 1)))]), fate: FixedFate([50]))
        _ = try await processor.play("Set up the company.")
        _ = try await processor.play("Run it for a month.")
        let date = try store.character().currentDate
        var acquire = output("The company acquires its server.")
        acquire.resolution.financialActions = [.init(action: .buyAsset, id: "server", name: "Server", amountMinor: 10_000, accountId: "website")]
        _ = try await TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(acquire)]), fate: FixedFate([50])).play("Buy the business server.")
        let sale = SaleProposal(id: "sale_one", businessId: "website", buyer: "Buyer", priceMinor: 20_000_000,
            effectiveFrom: date.iso, ownerJurisdiction: texas)
        try store.updateBusinessSimulation(saleProposals: [sale], expectedRevision: store.revision())
        let draft = try #require(store.businessSimulation().saleDrafts.first)
        let oldPersonal = try #require(store.accounts().first { $0.id == "personal" }).balanceMinor
        let oldCompany = try #require(store.accounts().first { $0.id == "website" }).balanceMinor
        try store.confirmBusinessSale(id: sale.id, expectedRevision: store.revision())
        let state = try store.businessSimulation()
        #expect(state.businesses.first?.status == .sold)
        #expect(state.obligations.allSatisfy { $0.endedOn == date })
        let companyAccount = try #require(store.accounts().first { $0.id == "website" })
        #expect(!companyAccount.isAccessible && companyAccount.status == .transferred && companyAccount.access == .none)
        #expect(companyAccount.balanceMinor == oldCompany)
        #expect(try store.accounts().first { $0.id == "personal" }?.balanceMinor == oldPersonal + sale.priceMinor - draft.estimatedTaxMinor)
        #expect(try store.balanceMinor() == oldPersonal + sale.priceMinor - draft.estimatedTaxMinor)
        let revision = try store.revision(), ledger = try store.ledger(limit: 100), positions = try store.positions()
        #expect(throws: ValidationError.self) { try store.confirmBusinessSale(id: sale.id, expectedRevision: revision) }
        #expect(throws: ValidationError.self) {
            try BankingEngine.manage(store: store, openings: [], changes: [], transfers: [
                .init(fromAccount: "website", toAccount: "personal", amountMinor: 1_000, reason: "Withdraw sold company money")], expectedRevision: revision)
        }
        #expect(throws: ValidationError.self) {
            try store.applyFinancialChanges(accountOpenings: [], streamChanges: [], ledger: [
                .init(date: date, sourceType: .expense, amountMinor: -1000, reason: "Spend sold cash", counterparty: nil, origin: .narrator, accountId: "website")], expectedRevision: revision)
        }
        for action in [FinancialAction(action: .sellAsset, id: "server", name: "Server", amountMinor: 10_000, accountId: "website"),
                       FinancialAction(action: .buyAsset, id: "new_server", name: "Another server", amountMinor: 1000, accountId: "website"),
                       FinancialAction(action: .borrow, id: "loan", name: "Company loan", amountMinor: 1000, accountId: "website")] {
            var invalid = output("You use the company funds."); invalid.resolution.financialActions = [action]
            let narrator = ScriptedNarrator(narrate: [.output(invalid)], repair: [.output(invalid)])
            await #expect(throws: TurnError.self) {
                _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50])).play("Attempt an action using the sold company account.")
            }
        }
        #expect(try store.revision() == revision && store.ledger(limit: 100) == ledger && store.positions() == positions)
        let history = try ContextBuilder.memory(store: store, input: "Remember the company sale and old salary agreement.")
        #expect(history.records.contains { $0.category == .business && $0.id == "sale:sale_one" })
        #expect(history.records.contains { $0.category == .obligation && $0.text.contains("owner_salary") })
        #expect(history.records.contains { $0.category == .assessment && $0.text.contains("revenueMinor") })
    }

    @Test func versionThreeMigrationPreservesCashTranscriptAndLegacyIncome() throws {
        let (library, id, store) = try chat()
        try BankingEngine.manage(store: store, openings: [.init(id: "website", name: "Website", kind: .business)], changes: [
            .init(action: .start, name: "Legacy profit", kind: .business, tier: nil, monthlyMinor: 5_000_000,
                  accountId: "website", effectiveFrom: start.iso, reason: "Existing net income")], transfers: [], expectedRevision: store.revision())
        try store.apply(TestChat.turn(playerText: "An existing action.", narration: "The old correction remains.", newDate: start))
        let balance = try store.balanceMinor(), ledger = try store.ledger(limit: 100), streams = try store.incomeStreams()
        let messages = try store.recentMessages(limit: 100), revision = try store.revision()
        let queue = try DatabaseQueue(path: library.fileURL(for: id).path)
        // Only this isolated fixture is restored to its v3 table shape before reopening.
        try queue.write { db in
            try db.execute(sql: """
                DROP TABLE simulation_records;
                ALTER TABLE accounts RENAME TO accounts_current;
                CREATE TABLE accounts (id TEXT PRIMARY KEY CHECK (length(trim(id)) > 0),
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK (length(trim(name)) > 0),
                    kind TEXT NOT NULL CHECK (kind IN ('personal', 'business', 'savings')));
                INSERT INTO accounts SELECT * FROM accounts_current;
                DROP TABLE accounts_current;
                DELETE FROM grdb_migrations WHERE identifier = 'v4';
                UPDATE session SET schema_version = 3;
                PRAGMA user_version = 3;
                """)
        }
        let migrated = try LifeStore.open(at: library.fileURL(for: id))
        #expect(try migrated.balanceMinor() == balance && migrated.ledger(limit: 100) == ledger)
        #expect(try migrated.incomeStreams() == streams && migrated.recentMessages(limit: 100) == messages)
        #expect(try migrated.revision() == revision && migrated.businessSimulation().businesses.isEmpty)
        #expect(try migrated.accounts().allSatisfy(\.isAccessible))
        #expect(try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 4)
    }

    @Test func saleRetainsOnlyExplicitPersonalLiabilitiesWithoutAdditionalCash() async throws {
        let (_, _, store) = try chat()
        let setup = company(on: start)
        try store.updateBusinessSimulation(businessChanges: setup.resolution.businessChanges!,
            obligationChanges: setup.resolution.obligationChanges!, expectedRevision: store.revision())
        var fixture = TestChat.turn(newDate: start, ledger: [
            .init(date: start, sourceType: .loan, amountMinor: 30_000, reason: "Existing company borrowing",
                  counterparty: nil, origin: .engine, accountId: "website")])
        fixture.positions = [
            .init(id: "guaranteed_loan", name: "Personally guaranteed loan", kind: .loan, principalMinor: 10_000,
                  openedOn: start, accountId: "website"),
            .init(id: "company_loan", name: "Company loan", kind: .loan, principalMinor: 20_000,
                  openedOn: start, accountId: "website")]
        try store.apply(fixture)
        let beforePersonal = try #require(store.accounts().first { $0.id == "personal" }).balanceMinor
        let beforeCompany = try #require(store.accounts().first { $0.id == "website" }).balanceMinor
        var proposal = SaleProposal(id: "retained_sale", businessId: "website", buyer: "Buyer", priceMinor: 20_000_000,
            effectiveFrom: start.iso, ownerJurisdiction: texas, retainedLiabilityIds: ["unknown_debt"])
        let revision = try store.revision()
        #expect(throws: ValidationError.self) {
            try store.updateBusinessSimulation(saleProposals: [proposal], expectedRevision: revision)
        }
        #expect(try store.revision() == revision && store.businessSimulation().saleDrafts.isEmpty)
        proposal.retainedLiabilityIds = ["guaranteed_loan"]
        try store.updateBusinessSimulation(saleProposals: [proposal], expectedRevision: revision)
        let draft = try #require(store.businessSimulation().saleDrafts.first)
        try store.confirmBusinessSale(id: proposal.id, expectedRevision: store.revision())
        let positions = try store.positions()
        #expect(positions.first { $0.id == "guaranteed_loan" }?.accountId == "personal")
        #expect(positions.first { $0.id == "company_loan" }?.accountId == "website")
        #expect(positions.reduce(Int64(0)) { $0 + $1.principalMinor } == 30_000)
        #expect(try store.accounts().first { $0.id == "website" }?.balanceMinor == beforeCompany)
        #expect(try store.balanceMinor() == beforePersonal + proposal.priceMinor - draft.estimatedTaxMinor)
        let afterSale = try store.ledger(limit: 100)
        var repayment = output("You repay your retained guarantee from personal funds.")
        repayment.resolution.financialActions = [.init(action: .repay, id: "guaranteed_loan", name: "Personally guaranteed loan",
            amountMinor: 10_000, accountId: "personal")]
        _ = try await TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(repayment)]), fate: FixedFate([50]))
            .play("Repay the retained personal guarantee.")
        #expect(try store.positions().first { $0.id == "guaranteed_loan" }?.principalMinor == 0)
        #expect(try store.positions().first { $0.id == "company_loan" }?.principalMinor == 20_000)
        #expect(try store.ledger(limit: 100).count == afterSale.count + 1)
        #expect(try store.balanceMinor() == beforePersonal + proposal.priceMinor - draft.estimatedTaxMinor - 10_000)
    }

    @Test func groundTruthIncludesCurrentBusinessPayrollAccessAndDatedFiscalRules() async throws {
        let (_, _, store) = try chat()
        let narrator = ScriptedNarrator(narrate: [.output(company(on: start)), .output(output("You read the accounts."))])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        _ = try await processor.play("Set up the company.")
        _ = try await processor.play("Review all current obligations.")
        let request = try #require(narrator.lastRequest)
        let prompt = PromptRenderer.render(request)
        for value in ["2004-01-01", "US-TX", "website_revenue", "owner_salary", "5000000", "150000", "Applicable fiscal profile", "access owner", "Default personal account: personal"] {
            #expect(prompt.user.contains(value), "Missing binding context: \(value)")
        }
        #expect(request.groundTruth.currentJurisdiction == texas)
    }

    @Test func datedMoveUsesEachJurisdictionsPricesAndMatchesSplitSkips() async throws {
        let (_, _, whole) = try chat(), (_, _, split) = try chat()
        let japan = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Tokyo")
        let moveDate = GameDate(year: 2004, month: 2, day: 15)
        for store in [whole, split] {
            var settings = try store.sessionSettings(); settings.household = .independent
            try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
            try store.applyFinancialChanges(accountOpenings: [], streamChanges: [], ledger: [
                .init(date: start, sourceType: .adjustment, amountMinor: 5_000_000, reason: "Fixture savings for relocation",
                      counterparty: nil, origin: .engine)], expectedRevision: store.revision())
        }
        let originalEconomy = try whole.economy()
        var long = output("You live in Texas until moving to Tokyo in mid-February.", time: .init(unit: .months, amount: 2))
        long.resolution.residenceChanges = [.init(jurisdiction: japan, effectiveFrom: moveDate, reason: "Move to Tokyo")]
        _ = try await TurnProcessor(store: whole, narrator: ScriptedNarrator(narrate: [.output(long)]), fate: FixedFate([50]))
            .play("Advance two months and move on February 15.")
        var second = long; second.resolution.timeAdvance = .init(unit: .months, amount: 1)
        let splitProcessor = TurnProcessor(store: split, narrator: ScriptedNarrator(narrate: [
            .output(output("January passes in Texas.", time: .init(unit: .months, amount: 1))), .output(second)]), fate: FixedFate([50]))
        _ = try await splitProcessor.play("Advance January.")
        _ = try await splitProcessor.play("Advance February, moving to Tokyo on February 15.")
        let expectedJapan = try CountryCatalog.shared.accountingEconomy(for: japan, on: start.adding(months: 2),
            accountingCurrency: "USD", minorUnitsPerUnit: 100)
        let bills = try whole.ledger(limit: 100).filter { $0.sourceType == .livingCost }
        #expect(bills.map(\.date.iso) == ["2004-03-01", "2004-02-01"])
        #expect(bills.map(\.amountMinor) == [-expectedJapan.monthlyLivingCostMinor, -originalEconomy.monthlyLivingCostMinor])
        #expect(try whole.economy().currency == "USD" && whole.economy().minorUnitsPerUnit == 100)
        #expect(try whole.economy().monthlyLivingCostMinor == expectedJapan.monthlyLivingCostMinor)
        #expect(try whole.geography().residence(on: moveDate.adding(days: -1)) == texas)
        #expect(try whole.geography().residence(on: moveDate) == japan)
        #expect(try whole.ledger(limit: 100) == split.ledger(limit: 100))
        #expect(try whole.accounts() == split.accounts() && whole.economy() == split.economy())
        #expect(try whole.businessSimulation() == split.businessSimulation())
    }

    @Test func unknownJurisdictionRejectsTheEntireMoveAndCashChange() async throws {
        let (_, _, store) = try chat()
        let geography = try store.geography(), economy = try store.economy(), ledger = try store.ledger(limit: 100)
        let revision = try store.revision()
        var invalid = output("The impossible move happens.", time: .init(unit: .months, amount: 1), money: [
            .init(sourceType: .adjustment, amountMinor: 10_000, reason: "Otherwise valid small correction")])
        invalid.resolution.residenceChanges = [.init(jurisdiction: .init(countryID: "Atlantis"), effectiveFrom: start, reason: "Move")]
        let narrator = ScriptedNarrator(narrate: [.output(invalid)], repair: [.output(invalid)])
        await #expect(throws: TurnError.self) {
            _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50])).play("Move and adjust cash.")
        }
        #expect(try store.geography() == geography && store.economy() == economy && store.ledger(limit: 100) == ledger)
        #expect(try store.revision() == revision && store.character().currentDate == start && store.recentMessages(limit: 10).isEmpty)
    }

    @Test func immediateMovePersistsConvertedEconomyAcrossUnrelatedTurnsAndReopening() async throws {
        let (library, id, store) = try chat()
        let japan = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Tokyo")
        var settings = try store.sessionSettings(); settings.household = .independent
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        try store.applyFinancialChanges(accountOpenings: [], streamChanges: [], ledger: [
            .init(date: start, sourceType: .adjustment, amountMinor: 5_000_000, reason: "Fixture relocation savings",
                  counterparty: nil, origin: .engine)], expectedRevision: store.revision())
        let beforeLedger = try store.ledger(limit: 100), beforeBalance = try store.balanceMinor()
        let expectedJapan = try CountryCatalog.shared.accountingEconomy(for: japan, on: start,
            accountingCurrency: "USD", minorUnitsPerUnit: 100)
        #expect(try store.economy().monthlyLivingCostMinor != expectedJapan.monthlyLivingCostMinor)
        var move = output("You arrive at your new home in Tokyo today.")
        move.resolution.residenceChanges = [.init(jurisdiction: japan, effectiveFrom: start, reason: "Move to Tokyo today")]
        _ = try await TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(move)]), fate: FixedFate([50]))
            .play("Move to Tokyo now, without advancing the date.")
        #expect(try store.character().currentDate == start && store.geography().residence(on: start) == japan)
        #expect(try store.economy() == expectedJapan)
        #expect(try store.ledger(limit: 100) == beforeLedger && store.balanceMinor() == beforeBalance)
        let reopened = try library.openChat(id: id)
        let narrator = ScriptedNarrator(narrate: [.output(output("You call an old friend.")),
            .output(output("A month passes at home in Tokyo.", time: .init(unit: .months, amount: 1)))])
        let processor = TurnProcessor(store: reopened, narrator: narrator, fate: FixedFate([50]))
        _ = try await processor.play("Call an old friend.")
        #expect(narrator.lastRequest?.groundTruth.currentJurisdiction == japan)
        #expect(narrator.lastRequest?.groundTruth.economy == expectedJapan)
        #expect(try reopened.economy() == expectedJapan && reopened.ledger(limit: 100) == beforeLedger)
        _ = try await processor.play("Remain here for one month.", skipTime: .init(unit: .months, amount: 1))
        let bills = try reopened.ledger(limit: 100).filter { $0.sourceType == .livingCost }
        #expect(bills.count == 1 && bills.first?.amountMinor == -expectedJapan.monthlyLivingCostMinor)
        #expect(try reopened.economy().currency == "USD" && reopened.balanceMinor() == beforeBalance - expectedJapan.monthlyLivingCostMinor)
    }

    @Test func conversionDuringSkipPreservesEarlierLegacyPayments() async throws {
        let (_, _, store) = try chat()
        try BankingEngine.manage(store: store, openings: [.init(id: "website", name: "Website", kind: .business)], changes: [
            .init(action: .start, name: "Legacy profit", kind: .business, tier: nil, monthlyMinor: 5_000_000,
                  accountId: "website", effectiveFrom: start.iso, reason: "Prior net-income arrangement")], transfers: [], expectedRevision: store.revision())
        let conversion = GameDate(year: 2004, month: 2, day: 15)
        var proposed = company(on: conversion)
        proposed.resolution.timeAdvance = .init(unit: .months, amount: 2)
        proposed.resolution.incomeStreams = [.init(action: .end, name: "Legacy profit", kind: nil, tier: nil,
            monthlyMinor: nil, effectiveFrom: conversion.iso)]
        _ = try await TurnProcessor(store: store, narrator: ScriptedNarrator(narrate: [.output(proposed)]), fate: FixedFate([50]))
            .play("Continue two months, converting to gross accounting on February 15.")
        let revenue = try store.ledger(limit: 100).filter { $0.sourceType == .businessProfit }.sorted { $0.date < $1.date }
        #expect(revenue.count == 2)
        #expect(revenue.first?.date.iso == "2004-02-01" && revenue.first?.amountMinor == 5_000_000)
        #expect(revenue.last?.date.iso == "2004-03-01" && revenue.last?.amountMinor == 5_000_000 * 15 / 29)
        #expect(try store.businessSimulation().businesses.first?.openedOn == conversion)
        #expect(try store.incomeStreams().first?.endedOn == conversion)
    }

    @Test func newAllowanceUsesReplacementPersonalAccountWhileExistingIncomeKeepsItsDestination() async throws {
        let (_, _, store) = try chat()
        let initial = try store.balanceMinor()
        try BankingEngine.manage(store: store, openings: [
            .init(id: "replacement", name: "Replacement personal", kind: .personal),
            .init(id: "savings", name: "Savings", kind: .savings)], changes: [
                .init(action: .start, name: "Existing family support", kind: .allowance, tier: nil, monthlyMinor: 5_000,
                      accountId: "savings", effectiveFrom: start.iso, reason: "Family deposits directly into savings")],
            transfers: [], expectedRevision: store.revision())
        try store.updateBusinessSimulation(accountChanges: [.init(action: .close, accountId: "personal",
            balanceDestinationAccountId: "replacement", replacementAccountId: "replacement")], expectedRevision: store.revision())
        var setup = output("Your family records the new support arrangement.")
        setup.resolution.incomeStreams = [
            .init(action: .start, name: "New allowance", kind: .allowance, tier: nil, monthlyMinor: 20_000,
                  effectiveFrom: start.iso, reason: "New family support into the default personal account"),
            .init(action: .change, name: "Existing family support", kind: nil, tier: nil, monthlyMinor: 10_000,
                  effectiveFrom: start.iso, reason: "Family increases the existing direct savings deposit")]
        let narrator = ScriptedNarrator(narrate: [.output(setup),
            .output(output("The following month's support arrives.", time: .init(unit: .months, amount: 1)))])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        _ = try await processor.play("Set up the new allowance and increase the old savings deposit.")
        let streams = try store.incomeStreams().filter { $0.endedOn == nil }
        #expect(streams.first { $0.name == "New allowance" }?.accountId == "replacement")
        #expect(streams.first { $0.name == "Existing family support" }?.accountId == "savings")
        _ = try await processor.play("Wait a month.", skipTime: .init(unit: .months, amount: 1))
        let accounts = try store.accounts()
        #expect(accounts.first { $0.id == "personal" }?.status == .closed)
        #expect(accounts.first { $0.id == "personal" }?.balanceMinor == 0)
        #expect(accounts.first { $0.id == "replacement" }?.balanceMinor == initial + 20_000)
        #expect(accounts.first { $0.id == "savings" }?.balanceMinor == 10_000)
        #expect(try store.businessSimulation().defaultPersonalAccountId == "replacement")
    }

    @Test func fiscalOverrideMatchesPresetJurisdictionDespiteDifferentLocalityText() async throws {
        let (_, _, store) = try chat()
        let preset = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13")
        let residence = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Tokyo apartment")
        let workplace = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Shibuya office")
        let override = FiscalOverrides(accountingUnitsPerLocalUnit: 0.02)
        try store.updateFiscalOverride(jurisdiction: preset, values: override, expectedRevision: store.revision())
        var move = output("You move to Tokyo and register the local company.")
        move.resolution.residenceChanges = [.init(jurisdiction: residence, effectiveFrom: start, reason: "Move to Tokyo")]
        move.resolution.businessChanges = [.init(action: .create, id: "tokyo", name: "Tokyo company", accountId: "tokyo",
            jurisdiction: workplace, legalStructure: .incorporated, effectiveFrom: start.iso)]
        move.resolution.obligationChanges = [.init(action: .start, id: "tokyo_revenue", businessId: "tokyo", kind: .revenue,
            name: "Company gross revenue", monthlyMinor: 5_000_000, fromAccountId: "tokyo", effectiveFrom: start.iso)]
        let narrator = ScriptedNarrator(narrate: [.output(move),
            .output(output("The company settles its first month.", time: .init(unit: .months, amount: 1)))])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        _ = try await processor.play("Move to Tokyo and open a local company using my saved conversion assumption.")
        let expected = try CountryCatalog.shared.accountingEconomy(for: residence, on: start,
            accountingCurrency: "USD", minorUnitsPerUnit: 100, overrides: override)
        #expect(try store.economy().monthlyLivingCostMinor == expected.monthlyLivingCostMinor)
        #expect(try store.economy().currency == "USD")
        _ = try await processor.play("Run the company for one month.", skipTime: .init(unit: .months, amount: 1))
        let assessment = try #require(store.businessSimulation().assessments.first)
        #expect(!assessment.profiles.isEmpty)
        #expect(assessment.profiles.allSatisfy { $0.conversion.accountingUnitsPerLocalUnit == 0.02 })
        #expect(try store.economy().monthlyLivingCostMinor == expected.monthlyLivingCostMinor)
    }
}
