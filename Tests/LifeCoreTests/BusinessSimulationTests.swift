import Foundation
import Testing
@testable import LifeCore

struct BusinessSimulationTests {
    let jan = GameDate(iso: "2004-01-01")!
    let feb = GameDate(iso: "2004-02-01")!
    let mar = GameDate(iso: "2004-03-01")!
    let april = GameDate(iso: "2004-04-01")!
    var economy: EconomyCard { .sampleUS2005 }
    var jurisdiction: JurisdictionRef { JurisdictionRef(countryID: "US", subdivisionID: "US-TX") }

    func setup(revenue: Int64 = 5_000_000, salary: Int64 = 150_000, staff: Int64? = nil) throws -> BusinessEngine.Plan {
        var changes = [ObligationChange(action: .start, id: "revenue", businessId: "vidshare", kind: .revenue,
            name: "Advertising", monthlyMinor: revenue, effectiveFrom: jan.iso)]
        if salary > 0 { changes.append(ObligationChange(action: .start, id: "owner-pay", businessId: "vidshare", kind: .ownerSalary,
            name: "Owner salary", monthlyMinor: salary, taxResidence: jurisdiction, effectiveFrom: jan.iso)) }
        if let staff { changes.append(ObligationChange(action: .start, id: "employees", businessId: "vidshare", kind: .payroll,
            name: "Developers", monthlyMinor: staff, headcount: 2, effectiveFrom: jan.iso)) }
        return try BusinessEngine.prepare(state: BusinessSimulationState(), accounts: [BankAccount(id: "personal", name: "Personal", kind: .personal, balanceMinor: 175_000)],
            start: jan, end: jan, economy: economy,
            businessChanges: [BusinessChange(action: .create, id: "vidshare", name: "Vidshare", accountId: "vidshare-bank", jurisdiction: jurisdiction)],
            obligationChanges: changes, revision: 1)
    }

    @Test func revenuePaysSalaryAndStaffWithoutCreatingCash() throws {
        let prepared = try setup(staff: 300_000)
        #expect(prepared.rejections.isEmpty)
        #expect(prepared.ledger.isEmpty)
        let result = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: feb, economy: economy)
        #expect(result.rejections.isEmpty)
        let statement = try #require(result.state.assessments.first)
        #expect(statement.revenueMinor == 5_000_000)
        #expect(statement.grossPayrollMinor == 750_000)
        #expect(result.state.payments.contains { $0.payableId.contains("owner-pay") && $0.grossMinor == 150_000 && $0.netMinor < 150_000 })
        let salary = try #require(result.state.payments.first { $0.payableId.contains("owner-pay") && !$0.payableId.contains(":employer") })
        #expect(result.accounts.first { $0.id == "personal" }?.balanceMinor == 175_000 + salary.netMinor)
        let netLedger = result.ledger.reduce(Int64(0)) { $0 + $1.amountMinor }
        let externalStaffNet = result.state.payments.filter { $0.payableId.contains(":employees:") && !$0.payableId.contains(":employer") }.reduce(Int64(0)) { $0 + $1.netMinor }
        #expect(netLedger == 5_000_000 - externalStaffNet)
        #expect(result.ledger.filter { $0.sourceType == .transfer }.reduce(0) { $0 + $1.amountMinor } == 0)
        #expect(result.accounts.contains { $0.kind == .taxReserve && !$0.isAccessible && $0.balanceMinor > 0 })
    }

    @Test func splitAndLongSkipsMatchIncludingPartialMonths() throws {
        let prepared = try setup(staff: 300_000)
        let long = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: april, economy: economy)
        let dates = [jan, GameDate(iso: "2004-01-19")!, feb, GameDate(iso: "2004-02-17")!, mar, april]
        var current = prepared
        var ledger: [NewLedgerEntry] = []
        for i in 0..<(dates.count - 1) {
            current = try BusinessEngine.settle(state: current.state, accounts: current.accounts, from: dates[i], to: dates[i + 1], economy: economy)
            ledger += current.ledger
        }
        #expect(current.accounts == long.accounts)
        #expect(current.state == long.state)
        #expect(ledger == long.ledger)
    }

    @Test func payrollShortfallIsProportionalAndOwnerWaits() throws {
        let prepared = try setup(revenue: 100_000, staff: 150_000)
        let result = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: feb, economy: economy)
        #expect(result.accounts.first { $0.id == "vidshare-bank" }?.balanceMinor == 0)
        #expect(result.accounts.first { $0.id == "personal" }?.balanceMinor == 175_000)
        #expect(result.state.payables.contains { $0.obligationId == "employees" && $0.remainingMinor > 0 })
        #expect(result.state.payables.contains { $0.obligationId == "owner-pay" && $0.remainingMinor == 150_000 })
        #expect(result.ledger.allSatisfy { $0.sourceType != .loan })
    }

    @Test func rateChangeProratesAndPreservesPriorAccrual() throws {
        let prepared = try setup(salary: 0)
        let middle = GameDate(iso: "2004-01-16")!
        let partial = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: middle, economy: economy)
        let changed = try BusinessEngine.prepare(state: partial.state, accounts: partial.accounts, start: middle, end: feb,
            economy: economy, obligationChanges: [ObligationChange(action: .change, id: "revenue", monthlyMinor: 10_000_000, effectiveFrom: middle.iso)], revision: 2)
        let result = try BusinessEngine.settle(state: changed.state, accounts: changed.accounts, from: middle, to: feb, economy: economy)
        let oldRate: Int64 = 5_000_000 * 15 / 31
        let newRate: Int64 = 10_000_000 * 16 / 31
        let expected = oldRate + newRate
        #expect(result.state.assessments.first?.revenueMinor == expected)
        #expect(result.state.obligations.count == 2)
    }

    @Test func saleRequiresExactRevisionAndTransfersAccountsWithoutTheirCash() throws {
        let prepared = try setup()
        let settled = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: feb, economy: economy)
        let proposal = SaleProposal(id: "sale", businessId: "vidshare", buyer: "Buyer Inc", priceMinor: 20_000_000, effectiveFrom: feb.iso, ownerJurisdiction: jurisdiction)
        let proposed = try BusinessEngine.prepare(state: settled.state, accounts: settled.accounts, start: feb, end: feb,
            economy: economy, saleProposals: [proposal], revision: 3)
        #expect(proposed.rejections.isEmpty)
        #expect(throws: ValidationError.self) {
            try BusinessEngine.confirmSale(id: "sale", expectedRevision: 3, currentRevision: 4, state: proposed.state, accounts: proposed.accounts, date: feb, economy: economy)
        }
        let result = try BusinessEngine.confirmSale(id: "sale", expectedRevision: 3, currentRevision: 3,
            state: proposed.state, accounts: proposed.accounts, date: feb, economy: economy)
        let tax = try #require(proposed.state.saleDrafts.first).estimatedTaxMinor
        let previousPersonal = try #require(proposed.accounts.first { $0.id == "personal" }).balanceMinor
        #expect(result.accounts.first { $0.id == "personal" }?.balanceMinor == previousPersonal + 20_000_000 - tax)
        #expect(result.accounts.filter { $0.businessId == "vidshare" }.allSatisfy { $0.status == .transferred && !$0.isAccessible })
        let following = try BusinessEngine.settle(state: result.state, accounts: result.accounts, from: feb, to: mar, economy: economy)
        #expect(following.ledger.isEmpty)
        #expect(throws: ValidationError.self) {
            try BusinessEngine.confirmSale(id: "sale", expectedRevision: 3, currentRevision: 3, state: result.state, accounts: result.accounts, date: feb, economy: economy)
        }
    }

    @Test func closingAccountRequiresResolutionAndRetainsHistory() throws {
        let accounts = [BankAccount(id: "personal", name: "Personal", kind: .personal, balanceMinor: 10_000),
                        BankAccount(id: "other", name: "Other", kind: .personal)]
        let invalid = try BusinessEngine.prepare(state: BusinessSimulationState(), accounts: accounts, start: jan, end: jan, economy: economy,
            accountChanges: [AccountLifecycleChange(action: .close, accountId: "personal")], revision: 1)
        #expect(!invalid.rejections.isEmpty)
        let valid = try BusinessEngine.prepare(state: BusinessSimulationState(), accounts: accounts, start: jan, end: jan, economy: economy,
            accountChanges: [AccountLifecycleChange(action: .close, accountId: "personal", balanceDestinationAccountId: "other", replacementAccountId: "other")], revision: 1)
        #expect(valid.rejections.isEmpty)
        #expect(valid.accounts.count == 2)
        #expect(valid.accounts.first { $0.id == "personal" }?.status == .closed)
        #expect(valid.accounts.first { $0.id == "other" }?.balanceMinor == 10_000)
        #expect(valid.state.defaultPersonalAccountId == "other")
        #expect(valid.ledger.reduce(0) { $0 + $1.amountMinor } == 0)
    }

    @Test func stateRoundTripsAndLegacyAccountsRemainAccessible() throws {
        let plan = try setup()
        let data = try OutputCoding.encoder.encode(plan.state)
        #expect(try OutputCoding.decoder.decode(BusinessSimulationState.self, from: data) == plan.state)
        let legacy = Data(#"{"id":"personal","name":"Personal","kind":"personal","balance_minor":100}"#.utf8)
        let account = try OutputCoding.decoder.decode(BankAccount.self, from: legacy)
        #expect(account.isAccessible)
    }

    @Test func taxesReserveThenRemitAndLossReconciliationDoesNotChargeTwice() throws {
        var prepared = try setup(salary: 0)
        prepared.state = try BusinessEngine.applyingFiscalOverride(BusinessFiscalOverride(jurisdiction: jurisdiction,
            effectiveFrom: jan, values: FiscalOverrides(businessTaxBasisPoints: 1_000)), to: prepared.state, at: jan, economy: economy)
        let first = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: feb, economy: economy)
        // The national override is 10%; Texas's separately disclosed 4.5% regional estimate remains.
        #expect(first.accounts.first { $0.kind == .taxReserve }?.balanceMinor == 725_000)
        #expect(first.ledger.filter { $0.reason.contains("Tax remittance") }.isEmpty)
        let second = try BusinessEngine.settle(state: first.state, accounts: first.accounts, from: feb, to: mar, economy: economy)
        #expect(second.ledger.filter { $0.reason.contains("Tax remittance") }.reduce(0) { $0 + $1.amountMinor } == -725_000)
        let changed = try BusinessEngine.prepare(state: second.state, accounts: second.accounts, start: mar, end: april,
            economy: economy, obligationChanges: [ObligationChange(action: .end, id: "revenue"),
                ObligationChange(action: .start, id: "loss", businessId: "vidshare", kind: .expense, name: "Operating loss", monthlyMinor: 12_000_000)], revision: 3)
        let final = try BusinessEngine.settle(state: changed.state, accounts: changed.accounts, from: mar, to: april, economy: economy)
        #expect(final.state.assessments.last?.businessTaxMinor == -1_450_000)
        #expect(final.accounts.first { $0.kind == .taxReserve }?.balanceMinor == 0)
        #expect(final.ledger.filter { $0.sourceType == .adjustment }.reduce(0) { $0 + $1.amountMinor } == 725_000)
        #expect(final.state.annualBusinessTaxAssessed.values.reduce(0, +) == 0)
    }

    @Test func explicitEmploymentDetailsEnforceEligibilityAndMinimumPay() throws {
        let prepared = try setup()
        let tooYoung = try BusinessEngine.prepare(state: prepared.state, accounts: prepared.accounts, start: jan, end: jan,
            economy: economy, obligationChanges: [ObligationChange(action: .start, id: "child", businessId: "vidshare", kind: .payroll,
                name: "Child worker", monthlyMinor: 100_000, employeeBirthDate: "2000-01-01", monthlyHours: 160)], revision: 2)
        #expect(tooYoung.rejections.contains { $0.contains("employment age") })
        let underpaid = try BusinessEngine.prepare(state: prepared.state, accounts: prepared.accounts, start: jan, end: jan,
            economy: economy, obligationChanges: [ObligationChange(action: .start, id: "underpaid", businessId: "vidshare", kind: .payroll,
                name: "Underpaid worker", monthlyMinor: 100, employeeBirthDate: "1980-01-01", monthlyHours: 160)], revision: 2)
        #expect(underpaid.rejections.contains { $0.contains("minimum") })
    }

    @Test func equalPriorityEmployeesShareShortfallsAndOldArrearsArePaidFirst() throws {
        let prepared = try setup(revenue: 100_000, salary: 0)
        var state = prepared.state
        state = try BusinessEngine.applyingFiscalOverride(BusinessFiscalOverride(jurisdiction: jurisdiction, effectiveFrom: jan,
            values: FiscalOverrides(incomeTaxBasisPoints: 0, employeeSocialBasisPoints: 0, employerContributionBasisPoints: 0, businessTaxBasisPoints: 0)),
            to: state, at: jan, economy: economy)
        let staff = try BusinessEngine.prepare(state: state, accounts: prepared.accounts, start: jan, end: jan, economy: economy,
            obligationChanges: [ObligationChange(action: .start, id: "one", businessId: "vidshare", kind: .payroll, name: "One", monthlyMinor: 100_000),
                ObligationChange(action: .start, id: "two", businessId: "vidshare", kind: .payroll, name: "Two", monthlyMinor: 100_000)], revision: 2)
        let result = try BusinessEngine.settle(state: staff.state, accounts: staff.accounts, from: jan, to: feb, economy: economy)
        #expect(result.state.payables.filter { $0.kind == .payroll }.allSatisfy { $0.paidMinor == 50_000 && $0.remainingMinor == 50_000 })
        let next = try BusinessEngine.settle(state: result.state, accounts: result.accounts, from: feb, to: mar, economy: economy)
        #expect(next.state.payables.filter { $0.kind == .payroll && $0.dueOn == feb }.allSatisfy { $0.remainingMinor == 0 })
        #expect(next.state.payables.filter { $0.kind == .payroll && $0.dueOn == mar }.allSatisfy { $0.paidMinor == 0 })
    }

    @Test func socialContributionCapsArePerEmployeeAcrossMonths() throws {
        let prepared = try setup(revenue: 100_000_000, salary: 0, staff: 10_000_000)
        let result = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: mar, economy: economy)
        #expect(result.state.assessments.count == 2)
        // Both people already exceeded the $87,900 Social Security cap in January;
        // only uncapped 1.45% Medicare remains in February for each $100,000 wage.
        #expect(result.state.assessments.last?.employerChargesMinor == 290_000)
        let reduced = try BusinessEngine.prepare(state: result.state, accounts: result.accounts, start: mar, end: mar,
            economy: economy, obligationChanges: [ObligationChange(action: .change, id: "employees", headcount: 1)], revision: 2)
        #expect(reduced.rejections.isEmpty)
        let next = try BusinessEngine.settle(state: reduced.state, accounts: reduced.accounts, from: mar, to: april, economy: economy)
        #expect(next.state.assessments.last?.employerChargesMinor == 145_000)
        let enlarged = try BusinessEngine.prepare(state: next.state, accounts: next.accounts, start: april, end: april,
            economy: economy, obligationChanges: [ObligationChange(action: .change, id: "employees", headcount: 2)], revision: 3)
        #expect(enlarged.rejections.contains { $0.contains("new hires") })
    }

    @Test func payrollSplitsAtUKAprilSixFiscalBoundary() throws {
        let start = GameDate(iso: "2004-04-01")!, end = GameDate(iso: "2004-05-01")!
        let gb = JurisdictionRef(countryID: "GB", subdivisionID: "GB-ENG")
        let prepared = try BusinessEngine.prepare(state: BusinessSimulationState(), accounts: [BankAccount(id: "personal", name: "Personal", kind: .personal)],
            start: start, end: start, economy: economy,
            businessChanges: [BusinessChange(action: .create, id: "uk-company", name: "UK company", accountId: "uk-bank", jurisdiction: gb)],
            obligationChanges: [ObligationChange(action: .start, id: "sales", businessId: "uk-company", kind: .revenue, name: "Sales", monthlyMinor: 10_000_000),
                ObligationChange(action: .start, id: "staff", businessId: "uk-company", kind: .payroll, name: "Staff", monthlyMinor: 300_000)], revision: 1)
        let result = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: start, to: end, economy: economy)
        #expect(result.state.annualPayrollPerPerson["staff:GB:2003"] == 50_000)
        #expect(result.state.annualPayrollPerPerson["staff:GB:2004"] == 250_000)
        #expect(result.state.assessments.first?.grossPayrollMinor == 300_000)
    }

    @Test func saleProposalWireAcronymAndStoredStateRoundTrip() throws {
        let raw = #"{"resolution":{"zoom":"scene","time_advance":{"unit":"days","amount":0},"money":[],"income_streams":[],"decisions":[],"life_state_changes":[],"cast_updates":[],"events":[],"sale_proposals":[{"id":"sale","business_id":"vidshare","buyer":"Buyer","price_minor":20000000,"ownership_bps":10000,"destination_account_id":"personal","effective_from":"2004-01-01","owner_jurisdiction":{"country_id":"US","subdivision_id":"US-TX","locality":null},"retained_liability_ids":null}]},"narration":"Review the proposed sale."}"#
        let output = try OutputCoding.decoder.decode(TurnOutput.self, from: Data(raw.utf8))
        let proposal = try #require(output.resolution.saleProposals?.first)
        #expect(proposal.ownershipBPS == 10_000)
        #expect(proposal.ownerJurisdiction == jurisdiction)
        #expect(try OutputCoding.decoder.decode(TurnOutput.self, from: OutputCoding.encoder.encode(output)) == output)
        #expect(try JSONDecoder().decode(SaleProposal.self, from: JSONEncoder().encode(proposal)) == proposal)
        let prepared = try setup()
        let proposed = try BusinessEngine.prepare(state: prepared.state, accounts: prepared.accounts, start: jan, end: jan,
            economy: economy, saleProposals: [proposal], revision: 2)
        #expect(proposed.rejections.isEmpty)
        #expect(try JSONDecoder().decode(BusinessSimulationState.self, from: JSONEncoder().encode(proposed.state)) == proposed.state)
    }

    @Test func accountNamesRemainUniqueIncludingClosedAccounts() throws {
        let accounts = [BankAccount(id: "personal", name: "Personal", kind: .personal),
                        BankAccount(id: "closed", name: "Vidshare", kind: .business, status: .closed, access: .none)]
        let result = try BusinessEngine.prepare(state: BusinessSimulationState(), accounts: accounts, start: jan, end: jan,
            economy: economy, businessChanges: [BusinessChange(action: .create, id: "vidshare", name: "vidshare", accountId: "new-account", jurisdiction: jurisdiction)],
            accountChanges: [AccountLifecycleChange(action: .rename, accountId: "personal", name: "VIDSHARE")], revision: 1)
        #expect(result.rejections.count == 2)
        #expect(result.accountOpenings.isEmpty)
    }

    @Test func sellingRecipientCompanyCancelsInternalTransfersAndPreservesRealUnpaidBills() throws {
        let source = try setup(revenue: 100_000, salary: 0)
        let prepared = try BusinessEngine.prepare(state: source.state, accounts: source.accounts, start: jan, end: jan,
            economy: economy,
            businessChanges: [BusinessChange(action: .create, id: "recipient", name: "Recipient company", accountId: "recipient-bank", jurisdiction: jurisdiction)],
            obligationChanges: [ObligationChange(action: .start, id: "internal-funding", businessId: "vidshare", kind: .transfer,
                name: "Internal funding", monthlyMinor: 300_000, toAccountId: "recipient-bank"),
                ObligationChange(action: .start, id: "service-bill", businessId: "vidshare", kind: .expense,
                    name: "Service bill", monthlyMinor: 200_000, toAccountId: "recipient-bank"),
                ObligationChange(action: .start, id: "owner-pay", businessId: "vidshare", kind: .ownerSalary,
                    name: "Owner salary", monthlyMinor: 100_000, taxResidence: jurisdiction)], revision: 2)
        #expect(prepared.rejections.isEmpty)
        let saleDate = GameDate(iso: "2004-02-15")!
        let beforeSale = try BusinessEngine.settle(state: prepared.state, accounts: prepared.accounts, from: jan, to: saleDate, economy: economy)
        let pastBill = try #require(beforeSale.state.payables.first { $0.obligationId == "service-bill" })
        let pastTransfer = try #require(beforeSale.state.payables.first { $0.obligationId == "internal-funding" })
        #expect(pastBill.paidMinor > 0 && pastBill.remainingMinor > 0)
        #expect(pastTransfer.paidMinor > 0 && pastTransfer.remainingMinor > 0)
        let proposed = try BusinessEngine.prepare(state: beforeSale.state, accounts: beforeSale.accounts, start: saleDate, end: saleDate,
            economy: economy, saleProposals: [SaleProposal(id: "recipient-sale", businessId: "recipient", buyer: "Buyer",
                priceMinor: 1_000_000, effectiveFrom: saleDate.iso, ownerJurisdiction: jurisdiction)], revision: 3)
        #expect(proposed.state.saleDrafts.first?.assumptions.contains { $0.contains("Internal funding") && $0.contains("Service bill") && $0.contains("remain owed") } == true)
        let sold = try BusinessEngine.confirmSale(id: "recipient-sale", expectedRevision: 3, currentRevision: 3,
            state: proposed.state, accounts: proposed.accounts, date: saleDate, economy: economy)
        let soldBalance = try #require(sold.accounts.first { $0.id == "recipient-bank" }).balanceMinor
        #expect(sold.state.obligations.count == beforeSale.state.obligations.count)
        #expect(sold.state.obligations.first { $0.id == "internal-funding" }?.endedOn == saleDate)
        #expect(sold.state.obligations.first { $0.id == "service-bill" }?.endedOn == nil)
        let cancelled = try #require(sold.state.payables.first { $0.id == pastTransfer.id })
        #expect(cancelled.paidMinor == pastTransfer.paidMinor && cancelled.remainingMinor == 0)
        #expect(cancelled.routingIssue?.contains("No cash moved") == true)
        #expect(sold.state.payables.first { $0.id == pastBill.id }?.remainingMinor == pastBill.remainingMinor)
        #expect(sold.ledger.allSatisfy { $0.accountId != "vidshare-bank" })

        // Both the old unpaid installment and the partial month's pending accrual must be safe.
        let following = try BusinessEngine.settle(state: sold.state, accounts: sold.accounts, from: saleDate, to: mar, economy: economy)
        #expect(following.rejections.isEmpty)
        #expect(following.accounts.first { $0.id == "recipient-bank" }?.balanceMinor == soldBalance)
        #expect(following.accounts.first { $0.id == "personal" }?.balanceMinor == sold.accounts.first { $0.id == "personal" }?.balanceMinor)
        #expect(following.ledger.allSatisfy { $0.accountId != "recipient-bank" })
        #expect(following.state.payables.filter { $0.obligationId == "internal-funding" }.count == 2)
        #expect(following.state.payables.filter { $0.obligationId == "internal-funding" }.allSatisfy { $0.remainingMinor == 0 })
        let outstanding = following.state.payables.filter { $0.obligationId == "service-bill" }.reduce(0) { $0 + $1.remainingMinor }
        #expect(outstanding == pastBill.remainingMinor + 200_000)
        #expect(following.state.payables.filter { $0.obligationId == "service-bill" }.allSatisfy { $0.routingIssue != nil })

        // Explicit routing repair preserves old partial-payment history and the full amount owed.
        let redirected = try BusinessEngine.prepare(state: following.state, accounts: following.accounts, start: mar, end: mar,
            economy: economy, obligationChanges: [ObligationChange(action: .change, id: "service-bill", toAccountId: "personal")], revision: 4)
        #expect(redirected.rejections.isEmpty)
        #expect(redirected.state.payables.first { $0.id == pastBill.id }?.paidMinor == pastBill.paidMinor)
        #expect(redirected.state.payables.filter { $0.obligationId == "service-bill" }.reduce(0) { $0 + $1.remainingMinor } == outstanding)
        #expect(redirected.ledger.isEmpty)
        let resumed = try BusinessEngine.settle(state: redirected.state, accounts: redirected.accounts, from: mar, to: april, economy: economy)
        #expect(resumed.accounts.first { $0.id == "recipient-bank" }?.balanceMinor == soldBalance)
        #expect(resumed.ledger.contains { $0.accountId == "personal" && $0.amountMinor > 0 })
        #expect(resumed.ledger.filter { $0.sourceType == .transfer }.reduce(0) { $0 + $1.amountMinor } == 0)
    }
}
