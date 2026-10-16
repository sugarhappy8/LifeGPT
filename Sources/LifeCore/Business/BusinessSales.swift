import Foundation

extension BusinessEngine {
    static func proposeSale(_ proposal: SaleProposal, start: GameDate, end: GameDate, economy: EconomyCard,
                            revision: Int, to plan: inout Plan) throws {
        try identifier(proposal.id); try label(proposal.buyer)
        let date = try effective(proposal.effectiveFrom, start: start, end: end)
        guard date == end else { throw invalid("Stop the turn on the sale date so its exact terms can be reviewed before time advances further.") }
        guard proposal.ownershipBPS == 10_000 else { throw invalid("Partial company sales require retained-ownership accounting and are not supported; this review supports a complete sale only.") }
        guard (1...1_000_000_000_000).contains(proposal.priceMinor),
              let business = plan.state.businesses.first(where: { $0.id == proposal.businessId }), active(business, on: date),
              let destination = plan.accounts.first(where: { $0.id == proposal.destinationAccountId }),
              destination.isAccessible, destination.businessId == nil else { throw invalid("A sale needs an active owned business, positive price and accessible personal destination.") }
        guard !plan.state.saleDrafts.contains(where: { $0.id == proposal.id && $0.confirmedOn != nil }) else { throw invalid("This sale was already completed.") }
        guard let ownerJurisdiction = proposal.ownerJurisdiction else { throw invalid("A company sale needs the owner's preset tax residence to calculate gains tax.") }
        let fiscal = try profile(ownerJurisdiction, on: date, economy: economy, state: plan.state)
        let gain = max(0, proposal.priceMinor - business.costBasisMinor)
        let annualKey = "\(fiscal.jurisdiction.countryID):\(fiscalYear(on: date, profile: fiscal))"
        let tax = try fiscal.capitalGainsTax(gainMinor: gain, yearToDateGainMinor: plan.state.annualCapitalGains[annualKey, default: 0])
        let accounts = plan.accounts.filter { $0.businessId == business.id && $0.status == .active }.map(\.id).sorted()
        let transferred = Set(accounts)
        let incoming = Set(plan.state.obligations.filter {
            $0.businessId != business.id && $0.toAccountId.map(transferred.contains) == true && ($0.endedOn == nil || $0.endedOn! >= date)
        }.map { "\($0.businessId): \($0.name)" }
            + plan.state.payables.filter { $0.businessId != business.id && $0.remainingMinor > 0 && $0.toAccountId.map(transferred.contains) == true }.map { "\($0.businessId): \($0.name)" }
            + plan.state.accruals.filter { $0.obligation.businessId != business.id && $0.obligation.toAccountId.map(transferred.contains) == true }.map { "\($0.obligation.businessId): \($0.obligation.name)" })
        var routingAssumptions: [String] = []
        if !incoming.isEmpty {
            routingAssumptions.append("Incoming arrangements from your other businesses: \(incoming.sorted().joined(separator: "; ")). Scheduled internal transfers end at the sale; unpaid and accrued transfer installments are cancelled without moving cash. Other payroll and expense amounts remain owed but cannot be paid into transferred accounts until their payment destination is explicitly changed.")
        }
        let draft = BusinessSaleDraft(proposal: proposal, reviewedRevision: revision, estimatedTaxMinor: tax,
            transferredAccountIds: accounts, confirmedOn: nil, fiscalProfile: fiscal,
            assumptions: ["Complete sale of company ownership, with its accounts and obligations. The recorded price is final consideration, not company cash plus price.",
                          "Gains use the recorded equity cost basis of \(Money.format(business.costBasisMinor, economy: economy)); bank balances and prior operating expenses do not automatically establish equity cost basis.",
                          "Gains tax uses the owner's recorded residence. No generic VAT or sales-tax percentage is applied to a share sale; local stamp duties, transfer levies, exemptions and transaction fees are unmodeled estimates of zero and require review."] + routingAssumptions)
        // Replacing an unconfirmed proposal creates a new exact review at the current revision.
        plan.state.saleDrafts.removeAll { $0.id == proposal.id && $0.confirmedOn == nil }
        plan.state.saleDrafts.append(draft)
    }

    /// This is an explicit user-confirmation endpoint; it must never be called from model changes.
    public static func confirmSale(id: String, expectedRevision: Int, currentRevision: Int,
                                   state: BusinessSimulationState, accounts: [BankAccount],
                                   date: GameDate, economy: EconomyCard) throws -> Plan {
        guard currentRevision == expectedRevision,
              let draft = state.saleDrafts.first(where: { $0.id == id }), draft.confirmedOn == nil,
              draft.reviewedRevision == expectedRevision,
              let effective = GameDate(iso: draft.proposal.effectiveFrom), effective == date,
              let index = state.businesses.firstIndex(where: { $0.id == draft.proposal.businessId }), active(state.businesses[index], on: date) else {
            throw invalid("The sale review is stale, already completed, or not on its effective date. Review the exact sale terms again.")
        }
        var plan = try settle(state: state, accounts: accounts, from: state.accruedThrough ?? date, to: date, economy: economy)
        try settleAccruals(at: date, onlyBusiness: draft.proposal.businessId, economy: economy, to: &plan)
        guard let destination = plan.accounts.first(where: { $0.id == draft.proposal.destinationAccountId }),
              destination.isAccessible, destination.businessId == nil else { throw invalid("The proceeds account is no longer accessible personal property.") }
        let business = plan.state.businesses[index]
        // Partial-month closeout can create a reserve; all company accounts transfer, not just cash visible in the preview.
        for i in plan.accounts.indices where plan.accounts[i].businessId == business.id && plan.accounts[i].status == .active {
            plan.accounts[i].status = .transferred; plan.accounts[i].access = .none
            plan.accounts[i].ownerId = draft.proposal.buyer
        }
        plan.state.businesses[index].status = .sold; plan.state.businesses[index].endedOn = date
        for i in plan.state.obligations.indices where plan.state.obligations[i].businessId == business.id {
            if plan.state.obligations[i].endedOn == nil || plan.state.obligations[i].endedOn! > date { plan.state.obligations[i].endedOn = date }
        }
        let transferred = Set(plan.accounts.filter { $0.businessId == business.id && $0.status == .transferred }.map(\.id))
        for i in plan.state.obligations.indices {
            let obligation = plan.state.obligations[i]
            guard obligation.businessId != business.id, obligation.kind == .transfer,
                  obligation.toAccountId.map(transferred.contains) == true else { continue }
            if obligation.endedOn == nil || obligation.endedOn! > date { plan.state.obligations[i].endedOn = date }
        }
        for i in plan.state.payables.indices {
            let payable = plan.state.payables[i]
            guard payable.businessId != business.id, payable.remainingMinor > 0,
                  payable.toAccountId.map(transferred.contains) == true else { continue }
            if payable.kind == .transfer {
                plan.state.payables[i].creditedMinor += payable.remainingMinor
                plan.state.payables[i].routingIssue = "Scheduled internal transfer cancelled on \(date.iso): destination transferred with \(business.name). No cash moved."
            } else {
                plan.state.payables[i].routingIssue = "Payment destination transferred with \(business.name) on \(date.iso). Amount remains owed; choose an accessible replacement destination."
            }
        }
        let net = max(0, draft.proposal.priceMinor - draft.estimatedTaxMinor)
        try post(draft.proposal.priceMinor, source: .assetSale, account: destination.id, date: date,
                 reason: "Sale of \(business.name) to \(draft.proposal.buyer)", to: &plan)
        if draft.estimatedTaxMinor > 0 {
            try post(-min(draft.proposal.priceMinor, draft.estimatedTaxMinor), source: .expense, account: destination.id,
                date: date, reason: "Company-sale gains tax: \(business.name) (net proceeds \(net))", to: &plan)
        }
        let annualKey = "\(draft.fiscalProfile.jurisdiction.countryID):\(fiscalYear(on: date, profile: draft.fiscalProfile))"
        plan.state.annualCapitalGains[annualKey] = try CheckedMoney.add(plan.state.annualCapitalGains[annualKey, default: 0], max(0, draft.proposal.priceMinor - business.costBasisMinor))
        if let i = plan.state.saleDrafts.firstIndex(where: { $0.id == id }) {
            plan.state.saleDrafts[i].confirmedOn = date
            plan.state.saleDrafts[i].transferredAccountIds = plan.accounts.filter { $0.businessId == business.id }.map(\.id).sorted()
        }
        syncMetadata(&plan)
        return plan
    }
}
