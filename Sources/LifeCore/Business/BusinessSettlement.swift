import Foundation

private struct BusinessTaxSlice: Hashable {
    var jurisdiction: JurisdictionRef
    var date: GameDate
}

extension BusinessEngine {
    public static func settle(state: BusinessSimulationState, accounts: [BankAccount], from start: GameDate,
                              to end: GameDate, economy: EconomyCard) throws -> Plan {
        guard end >= start, end.daysSince(start) <= 366_000 else { throw invalid("Business settlement dates are invalid.") }
        if let through = state.accruedThrough, through != start { throw invalid("Business settlement must continue from its last accrued date.") }
        var plan = Plan(state: state, accounts: accounts)
        var payrollProfileCache: [String: FiscalProfile] = [:]
        var day = start
        while day < end {
            let monthStart = GameDate(year: day.year, month: day.month, day: 1)
            for obligation in plan.state.obligations where obligation.effectiveFrom <= day && (obligation.endedOn == nil || day < obligation.endedOn!) {
                guard let business = plan.state.businesses.first(where: { $0.id == obligation.businessId }), active(business, on: day) else { continue }
                guard plan.accounts.contains(where: { $0.id == obligation.fromAccountId && $0.isAccessible }) else { throw invalid("An active business obligation uses an inaccessible account.") }
                let jurisdiction = business.jurisdiction(on: day)
                let relevantJurisdictions = [jurisdiction, obligation.jurisdiction ?? jurisdiction, obligation.taxResidence ?? jurisdiction]
                let changedRules = plan.state.fiscalOverrides.filter { change in
                    change.effectiveFrom <= day && change.effectiveFrom >= monthStart && relevantJurisdictions.contains {
                        $0.countryID == change.jurisdiction.countryID && $0.subdivisionID == change.jurisdiction.subdivisionID
                    }
                }.map(\.effectiveFrom).max() ?? monthStart
                let movedBusiness = business.jurisdictions.filter { $0.effectiveFrom <= day }.map(\.effectiveFrom).max() ?? monthStart
                var ruleDate = max(monthStart, max(changedRules, movedBusiness))
                if obligation.kind == .payroll || obligation.kind == .ownerSalary {
                    for taxJurisdiction in [obligation.jurisdiction ?? jurisdiction, obligation.taxResidence ?? jurisdiction] {
                        let key = "\(taxJurisdiction.countryID):\(taxJurisdiction.subdivisionID ?? ""):\(ruleDate.iso)"
                        let rules: FiscalProfile
                        if let cached = payrollProfileCache[key] { rules = cached }
                        else { rules = try profile(taxJurisdiction, on: ruleDate, economy: economy, state: plan.state); payrollProfileCache[key] = rules }
                        let fiscalStart = GameDate(year: fiscalYear(on: day, profile: rules), month: rules.taxYearStartMonth, day: rules.taxYearStartDay)
                        ruleDate = max(ruleDate, fiscalStart)
                    }
                }
                if let i = plan.state.accruals.firstIndex(where: { $0.obligation == obligation && $0.periodStart == monthStart && $0.businessJurisdiction == jurisdiction && $0.ruleDate == ruleDate }) {
                    plan.state.accruals[i].numerator = try CheckedMoney.add(plan.state.accruals[i].numerator, obligation.monthlyMinor)
                } else {
                    plan.state.accruals.append(BusinessAccrual(obligation: obligation, businessJurisdiction: jurisdiction, ruleDate: ruleDate, periodStart: monthStart,
                        numerator: obligation.monthlyMinor, daysInPeriod: GameDate.daysInMonth(year: day.year, month: day.month)))
                }
            }
            day = day.adding(days: 1)
            for obligation in plan.state.obligations where obligation.effectiveFrom == day {
                rerouteBlockedPayments(for: obligation, on: day, to: &plan)
            }
            if day.day == 1 { try settleAccruals(at: day, onlyBusiness: nil, economy: economy, to: &plan) }
            for change in plan.state.pendingAccountChanges.filter({ GameDate(iso: $0.effectiveFrom ?? "") == day }) {
                do { try applyAccountChange(change, date: day, to: &plan) }
                catch { plan.rejections.append("account_lifecycle \(change.accountId): \(error.localizedDescription)") }
                plan.state.pendingAccountChanges.removeAll { $0 == change }
            }
        }
        for i in plan.state.businesses.indices where plan.state.businesses[i].status == .active {
            if let ending = plan.state.businesses[i].endedOn, ending <= end { plan.state.businesses[i].status = .ended }
        }
        plan.state.accruedThrough = end
        syncMetadata(&plan)
        return plan
    }

    static func settleAccruals(at date: GameDate, onlyBusiness: String?, economy: EconomyCard, to plan: inout Plan) throws {
        let accruals = plan.state.accruals.filter { onlyBusiness == nil || $0.obligation.businessId == onlyBusiness }
        for businessId in Set(accruals.map { $0.obligation.businessId }).sorted() {
            guard let business = plan.state.businesses.first(where: { $0.id == businessId }), business.status != .sold else { continue }
            let records = accruals.filter { $0.obligation.businessId == businessId }
            let period = records.map(\.periodStart).min() ?? date
            let businessProfile = try profile(business.jurisdiction(on: period), on: period, economy: economy, state: plan.state)
            var profiles: [FiscalProfile] = [businessProfile]
            var assumptions = ["Monthly accrual accounting; payroll rules and annual caps follow the period earned, including unpaid wages, rather than statutory cash-payment timing. Tax remittance occurs on the following monthly boundary. Company accounting uses an elected calendar year; personal payroll follows the profile's fiscal year."]
            if business.legalStructure == .soleProprietor {
                assumptions.append("Sole-proprietor estimate uses ordinary personal income and combined social contribution rates on profit; special self-employment deductions and treaty relief are not modeled.")
            }
            var revenue: Int64 = 0, payroll: Int64 = 0, employer: Int64 = 0, expenses: Int64 = 0
            var profitByJurisdiction: [BusinessTaxSlice: Int64] = [:]
            let assessmentId = "\(businessId):\(period.iso):\(date.iso)"
            guard !plan.state.assessments.contains(where: { $0.id == assessmentId }) else { throw invalid("This business period was already assessed.") }
            for (sequence, accrual) in records.enumerated() {
                let o = accrual.obligation
                let taxSlice = BusinessTaxSlice(jurisdiction: accrual.businessJurisdiction, date: accrual.ruleDate)
                let perPerson = accrual.numerator / Int64(accrual.daysInPeriod)
                guard perPerson > 0 else { continue }
                let amount = try multiply(perPerson, Int64(o.headcount))
                let payableId = "\(assessmentId):\(o.id):\(sequence)"
                switch o.kind {
                case .revenue:
                    try post(amount, source: .businessProfit, account: o.fromAccountId, date: date,
                             reason: "Gross revenue: \(o.name), \(period.iso)–\(date.iso)", to: &plan)
                    revenue = try CheckedMoney.add(revenue, amount)
                    profitByJurisdiction[taxSlice] = try CheckedMoney.add(profitByJurisdiction[taxSlice, default: 0], amount)
                case .payroll, .ownerSalary:
                    if o.kind == .payroll && (o.employeeBirthDate == nil || o.monthlyHours == nil) {
                        assumptions.append("\(o.name): employment-age and minimum-hourly-pay checks require a recorded birth date and monthly hours; absent details are not verified.")
                    }
                    let fiscal = try profile(o.jurisdiction ?? accrual.businessJurisdiction, on: accrual.ruleDate, economy: economy, state: plan.state)
                    if !profiles.contains(fiscal) { profiles.append(fiscal) }
                    let employeeKey = o.kind == .ownerSalary ? "owner" : o.id
                    let annualKey = "\(employeeKey):\(fiscal.jurisdiction.countryID):\(fiscalYear(on: accrual.ruleDate, profile: fiscal))"
                    let ytd = plan.state.annualPayrollPerPerson[annualKey, default: 0]
                    let calculation = try fiscal.calculatePayroll(grossMinor: perPerson, yearToDateGrossMinor: ytd, employeeCount: o.headcount)
                    plan.state.annualPayrollPerPerson[annualKey] = try CheckedMoney.add(ytd, perPerson)
                    var incomeTax = calculation.incomeTaxMinor
                    if let residence = o.taxResidence, residence != fiscal.jurisdiction {
                        assumptions.append("\(o.name): cross-border estimate uses work-jurisdiction social charges and residence income tax without treaty credits or dual-filing reconciliation.")
                        let residenceRules = try profile(residence, on: accrual.ruleDate, economy: economy, state: plan.state)
                        if !profiles.contains(residenceRules) { profiles.append(residenceRules) }
                        let residenceKey = "\(employeeKey):residence:\(residence.countryID):\(fiscalYear(on: accrual.ruleDate, profile: residenceRules))"
                        let previous = plan.state.annualPayrollPerPerson[residenceKey, default: 0]
                        incomeTax = try residenceRules.calculatePayroll(grossMinor: perPerson, yearToDateGrossMinor: previous, employeeCount: o.headcount).incomeTaxMinor
                        plan.state.annualPayrollPerPerson[residenceKey] = try CheckedMoney.add(previous, perPerson)
                    }
                    let withholding = min(amount, try CheckedMoney.add(incomeTax, calculation.employeeSocialMinor))
                    payroll = try CheckedMoney.add(payroll, amount)
                    employer = try CheckedMoney.add(employer, calculation.employerContributionMinor)
                    profitByJurisdiction[taxSlice] = try CheckedMoney.add(profitByJurisdiction[taxSlice, default: 0], -calculation.totalEmployerCostMinor)
                    plan.state.payables.append(payable(id: payableId, business: businessId, obligation: o.id, name: o.name,
                        kind: o.kind == .ownerSalary ? .ownerSalary : .payroll, date: date, from: o.fromAccountId,
                        to: o.toAccountId, amount: amount, withholding: withholding))
                    if calculation.employerContributionMinor > 0 {
                        let reserve = try reserveAccount(for: business, date: date, to: &plan)
                        plan.state.payables.append(payable(id: payableId + ":employer", business: businessId, obligation: o.id,
                            name: "Employer charges: \(o.name)", kind: .tax, date: date, from: o.fromAccountId,
                            to: reserve, amount: calculation.employerContributionMinor))
                    }
                case .expense, .transfer:
                    if o.kind == .expense {
                        expenses = try CheckedMoney.add(expenses, amount)
                        profitByJurisdiction[taxSlice] = try CheckedMoney.add(profitByJurisdiction[taxSlice, default: 0], -amount)
                    }
                    var installment = payable(id: payableId, business: businessId, obligation: o.id, name: o.name,
                        kind: o.kind == .expense ? .expense : .transfer, date: date, from: o.fromAccountId,
                        to: o.toAccountId, amount: amount)
                    if o.kind == .transfer, let destination = o.toAccountId,
                       plan.accounts.first(where: { $0.id == destination })?.status == .transferred {
                        installment.creditedMinor = amount
                        installment.routingIssue = "Accrued internal transfer cancelled: destination was transferred with a sold company. No cash moved."
                        assumptions.append("\(o.name): accrued internal transfer cancelled because the destination belongs to a sold company; no cash moved.")
                    }
                    plan.state.payables.append(installment)
                }
            }
            let deductions = try CheckedMoney.add(try CheckedMoney.add(payroll, employer), expenses)
            let profit = revenue - deductions
            var tax: Int64 = 0
            for slice in profitByJurisdiction.keys.sorted(by: { ($0.date, $0.jurisdiction.countryID, $0.jurisdiction.subdivisionID ?? "") < ($1.date, $1.jurisdiction.countryID, $1.jurisdiction.subdivisionID ?? "") }) {
                let jurisdiction = slice.jurisdiction
                let fiscal = try profile(jurisdiction, on: slice.date, economy: economy, state: plan.state)
                if !profiles.contains(fiscal) { profiles.append(fiscal) }
                // Moving between regions must not reset the national annual brackets.
                let annualKey = "\(businessId):\(jurisdiction.countryID):\(slice.date.year)"
                let priorProfit = plan.state.annualBusinessProfit[annualKey, default: 0]
                let updatedProfit = try CheckedMoney.add(priorProfit, profitByJurisdiction[slice, default: 0])
                let priorAssessment = plan.state.annualBusinessTaxAssessed[annualKey, default: 0]
                let taxableChange = max(0, updatedProfit) - max(0, priorProfit)
                let difference: Int64
                if taxableChange >= 0 {
                    difference = try businessTaxIncrement(taxableChange, before: max(0, priorProfit), business: business, fiscal: fiscal)
                } else {
                    difference = -min(priorAssessment, try businessTaxIncrement(-taxableChange, before: max(0, updatedProfit), business: business, fiscal: fiscal))
                }
                let liability = try CheckedMoney.add(priorAssessment, difference)
                plan.state.annualBusinessProfit[annualKey] = updatedProfit
                plan.state.annualBusinessTaxAssessed[annualKey] = liability
                tax = try CheckedMoney.add(tax, difference)
                let taxId = "business-tax:\(annualKey)"
                if difference > 0 {
                    let reserve = try reserveAccount(for: business, date: date, to: &plan)
                    plan.state.payables.append(payable(id: assessmentId + ":" + slice.date.iso + ":" + taxId, business: businessId, obligation: taxId,
                        name: "Business tax", kind: .tax, date: date, from: business.accountId, to: reserve, amount: difference))
                } else if difference < 0 {
                    try reconcileTaxReduction(-difference, obligationId: taxId, business: business, date: date, to: &plan)
                }
            }
            plan.state.assessments.append(BusinessAssessment(id: assessmentId, businessId: businessId,
                periodStart: period, periodEnd: date, revenueMinor: revenue, grossPayrollMinor: payroll,
                employerChargesMinor: employer, expensesMinor: expenses, taxableProfitMinor: profit,
                businessTaxMinor: tax, profiles: profiles, assumptions: Array(Set(assumptions)).sorted()))
        }
        plan.state.accruals.removeAll { onlyBusiness == nil || $0.obligation.businessId == onlyBusiness }
        try payDue(at: date, onlyBusiness: onlyBusiness, to: &plan)
    }

    static func businessTaxIncrement(_ amount: Int64, before: Int64, business: BusinessRecord, fiscal: FiscalProfile) throws -> Int64 {
        if business.legalStructure == .incorporated { return try fiscal.businessTax(taxableProfitMinor: amount, yearToDateProfitMinor: before) }
        let estimate = try fiscal.calculatePayroll(grossMinor: amount, yearToDateGrossMinor: before)
        return min(amount, try CheckedMoney.add(try CheckedMoney.add(estimate.incomeTaxMinor, estimate.employeeSocialMinor), estimate.employerContributionMinor))
    }

    /// Oldest first, then proportional within equal account/date/priority groups.
    static func payDue(at date: GameDate, onlyBusiness: String?, to plan: inout Plan) throws {
        for i in plan.state.payables.indices where plan.state.payables[i].remainingMinor > 0 {
            let payable = plan.state.payables[i]
            guard plan.state.businesses.first(where: { $0.id == payable.businessId })?.status != .sold else { continue }
            if !canReceive(payable, accounts: plan.accounts) {
                plan.state.payables[i].routingIssue = "Payment destination is inaccessible. Amount remains owed; explicitly change the recurring record's destination before payment."
            }
        }
        let groups = Dictionary(grouping: plan.state.payables.indices.filter {
            let p = plan.state.payables[$0]
            return p.remainingMinor > 0 && p.dueOn <= date && (onlyBusiness == nil || p.businessId == onlyBusiness)
                && plan.state.businesses.first(where: { $0.id == p.businessId })?.status != .sold
        }) { index in
            let p = plan.state.payables[index]
            return "\(p.priority):\(p.dueOn.iso):\(p.fromAccountId)"
        }
        var heldForBlocked: [String: Int64] = [:]
        for key in groups.keys.sorted() {
            let indices = groups[key]!.sorted { plan.state.payables[$0].id < plan.state.payables[$1].id }
            guard let first = indices.first, let source = plan.accounts.first(where: { $0.id == plan.state.payables[first].fromAccountId }),
                  source.status == .active else { continue }
            let total = try indices.reduce(Int64(0)) { try CheckedMoney.add($0, plan.state.payables[$1].remainingMinor) }
            let available = min(max(0, source.balanceMinor - heldForBlocked[source.id, default: 0]), total)
            guard available > 0 else { continue }
            var shares = indices.map { CheckedMoney.fraction(available, numerator: plan.state.payables[$0].remainingMinor, denominator: total) }
            var spare = available - shares.reduce(0, +)
            for i in shares.indices where spare > 0 && shares[i] < plan.state.payables[indices[i]].remainingMinor {
                shares[i] += 1; spare -= 1
            }
            for (offset, index) in indices.enumerated() {
                let amount = shares[offset]
                guard amount > 0 else { continue }
                let p = plan.state.payables[index]
                guard canReceive(p, accounts: plan.accounts) else {
                    // Keep this priority's share available for routing repair, rather than paying
                    // a lower-priority owner salary ahead of blocked employee/expense claims.
                    heldForBlocked[source.id, default: 0] += amount
                    continue
                }
                guard let business = plan.state.businesses.first(where: { $0.id == p.businessId }) else { continue }
                let totalPaid = try CheckedMoney.add(p.paidMinor, amount)
                let shouldReserve = CheckedMoney.fraction(p.withholdingMinor, numerator: totalPaid, denominator: p.amountMinor)
                let withholding = max(0, shouldReserve - p.reservedMinor)
                let net = amount - withholding
                if p.toAccountId == nil && withholding > 0 {
                    try post(-net, source: .expense, account: p.fromAccountId, date: date,
                             reason: "\(p.name): external net pay (due \(p.dueOn.iso))", to: &plan)
                    try post(-withholding, source: .transfer, account: p.fromAccountId, date: date,
                             reason: "Payroll deductions sent to reserve: \(p.name)", to: &plan)
                } else {
                    try post(-amount, source: p.toAccountId != nil ? .transfer : .expense, account: p.fromAccountId,
                             date: date, reason: "\(p.name) (due \(p.dueOn.iso))", to: &plan)
                }
                if let destination = p.toAccountId, net > 0 {
                    try post(net, source: .transfer, account: destination, date: date, reason: "\(p.name): net receipt", to: &plan)
                    if plan.accounts.first(where: { $0.id == destination })?.kind == .taxReserve {
                        appendRemittance(amount: net, from: destination, p: p, date: date, to: &plan)
                    }
                }
                if withholding > 0 {
                    let reserve = try reserveAccount(for: business, date: date, to: &plan)
                    try post(withholding, source: .transfer, account: reserve, date: date, reason: "Payroll deductions reserved: \(p.name)", to: &plan)
                    appendRemittance(amount: withholding, from: reserve, p: p, date: date, to: &plan)
                }
                plan.state.payables[index].paidMinor = totalPaid
                plan.state.payables[index].reservedMinor = shouldReserve
                plan.state.payments.append(BusinessPayment(id: "payment:\(plan.state.payments.count):\(p.id)", payableId: p.id,
                    date: date, grossMinor: amount, withheldMinor: withholding, netMinor: net))
            }
        }
    }

    static func canReceive(_ payable: BusinessPayable, accounts: [BankAccount]) -> Bool {
        guard let destination = payable.toAccountId else { return true }
        guard let account = accounts.first(where: { $0.id == destination }), account.status == .active else { return false }
        return account.isAccessible || (payable.kind == .tax && account.kind == .taxReserve && account.businessId == payable.businessId)
    }

    /// An explicit destination change resolves blocked arrears without changing already paid ledger entries.
    static func rerouteBlockedPayments(for obligation: RecurringObligation, on date: GameDate, to plan: inout Plan) {
        guard let destination = obligation.toAccountId, plan.accounts.contains(where: { $0.id == destination && $0.isAccessible }) else { return }
        for i in plan.state.payables.indices {
            let prior = plan.state.payables[i]
            guard prior.businessId == obligation.businessId, prior.obligationId == obligation.id,
                  prior.remainingMinor > 0, !canReceive(prior, accounts: plan.accounts) else { continue }
            var redirected = prior
            redirected.id = "rerouted:\(plan.state.payables.count):\(prior.id)"
            redirected.toAccountId = destination; redirected.amountMinor = prior.remainingMinor
            redirected.paidMinor = 0; redirected.creditedMinor = 0; redirected.refundedMinor = 0
            redirected.withholdingMinor = min(prior.remainingMinor, max(0, prior.withholdingMinor - prior.reservedMinor))
            redirected.reservedMinor = 0; redirected.routingIssue = nil
            plan.state.payables[i].creditedMinor += prior.remainingMinor
            plan.state.payables[i].routingIssue = "Unpaid amount redirected to \(destination) on \(date.iso); previous payments remain in the ledger."
            plan.state.payables.append(redirected)
        }
        for i in plan.state.accruals.indices {
            let prior = plan.state.accruals[i].obligation
            guard prior.businessId == obligation.businessId, prior.id == obligation.id,
                  let oldDestination = prior.toAccountId, oldDestination != destination,
                  !plan.accounts.contains(where: { $0.id == oldDestination && $0.isAccessible }) else { continue }
            plan.state.accruals[i].obligation.toAccountId = destination
        }
    }

    static func appendRemittance(amount: Int64, from account: String, p: BusinessPayable, date: GameDate, to plan: inout Plan) {
        let due = GameDate(year: date.year, month: date.month, day: 1).adding(months: 1)
        plan.state.payables.append(payable(id: "remittance:\(plan.state.payables.count):\(p.id)", business: p.businessId,
            obligation: p.obligationId, name: "Tax remittance: \(p.name)", kind: .tax, date: due, from: account, to: nil, amount: amount))
    }

    /// Reconcile cumulative fiscal-year losses against this year's assessments. Cancel unpaid
    /// liabilities first, release funded reserves second, then refund only previously remitted tax.
    static func reconcileTaxReduction(_ amount: Int64, obligationId: String, business: BusinessRecord,
                                      date: GameDate, to plan: inout Plan) throws {
        var remaining = amount
        let taxIndices = plan.state.payables.indices.filter {
            plan.state.payables[$0].obligationId == obligationId && plan.state.payables[$0].fromAccountId == business.accountId
        }
        for i in taxIndices where remaining > 0 {
            let credit = min(remaining, plan.state.payables[i].remainingMinor)
            plan.state.payables[i].creditedMinor += credit; remaining -= credit
        }
        let reserveId = "_engine_tax_\(business.id)"
        let remittances = plan.state.payables.indices.filter {
            plan.state.payables[$0].obligationId == obligationId && plan.state.payables[$0].fromAccountId == reserveId
        }
        for i in remittances where remaining > 0 {
            let credit = min(remaining, plan.state.payables[i].remainingMinor)
            guard credit > 0 else { continue }
            plan.state.payables[i].creditedMinor += credit; remaining -= credit
            try post(-credit, source: .transfer, account: reserveId, date: date, reason: "Tax reconciliation: excess reserve released", to: &plan)
            try post(credit, source: .transfer, account: business.accountId, date: date, reason: "Tax reconciliation: reserve returned", to: &plan)
        }
        if remaining > 0 {
            let remitted = try remittances.reduce(Int64(0)) { try CheckedMoney.add($0, plan.state.payables[$1].paidMinor - plan.state.payables[$1].refundedMinor) }
            guard remaining <= remitted else { throw invalid("Tax reconciliation exceeds recorded tax payments.") }
            var toCredit = remaining
            for i in remittances where toCredit > 0 {
                let credit = min(toCredit, max(0, plan.state.payables[i].paidMinor - plan.state.payables[i].refundedMinor))
                plan.state.payables[i].refundedMinor += credit; toCredit -= credit
            }
            try post(remaining, source: .adjustment, account: business.accountId, date: date,
                reason: "Tax reconciliation refund of previously remitted business tax", to: &plan)
        }
    }

    static func reserveAccount(for business: BusinessRecord, date: GameDate, to plan: inout Plan) throws -> String {
        let id = "_engine_tax_\(business.id)"
        if let existing = plan.accounts.first(where: { $0.id == id }) {
            guard existing.kind == .taxReserve, existing.businessId == business.id, existing.status == .active else { throw invalid("The business tax reserve is unavailable.") }
        } else {
            let baseName = "Tax reserve · \(business.name.prefix(70))"
            var name = baseName, suffix = 2
            while plan.accounts.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                name = "\(baseName) (\(suffix))"; suffix += 1
            }
            plan.accounts.append(BankAccount(id: id, name: name, kind: .taxReserve,
                ownerId: business.id, businessId: business.id, openedOn: date, access: .restricted))
            plan.accountOpenings.append(AccountOpening(id: id, name: name, kind: .taxReserve))
        }
        return id
    }

    static func payable(id: String, business: String, obligation: String, name: String, kind: BusinessPayable.Kind,
                        date: GameDate, from: String, to: String?, amount: Int64, withholding: Int64 = 0) -> BusinessPayable {
        BusinessPayable(id: id, businessId: business, obligationId: obligation, name: name, kind: kind, dueOn: date,
            fromAccountId: from, toAccountId: to, amountMinor: amount, paidMinor: 0, creditedMinor: 0, refundedMinor: 0,
            withholdingMinor: min(amount, max(0, withholding)), reservedMinor: 0)
    }
}
