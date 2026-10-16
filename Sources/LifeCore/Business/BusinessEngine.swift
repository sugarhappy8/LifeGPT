import Foundation

/// Deterministic, side-effect-free business accounting. Persist an entire Plan atomically.
public enum BusinessEngine {
    public struct Plan: Sendable {
        public var state: BusinessSimulationState
        public var accounts: [BankAccount]
        public var ledger: [NewLedgerEntry] = []
        public var accountOpenings: [AccountOpening] = []
        public var rejections: [String] = []
        public var accountBalances: [String: Int64] { Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balanceMinor) }) }
        public init(state: BusinessSimulationState, accounts: [BankAccount]) {
            self.state = state; self.accounts = BusinessEngine.applyingMetadata(state: state, to: accounts)
        }
    }

    public static func applyingMetadata(state: BusinessSimulationState, to accounts: [BankAccount]) -> [BankAccount] {
        accounts.map { account in
            guard let metadata = state.accountMetadata.first(where: { $0.id == account.id }) else { return account }
            var a = account
            a.name = metadata.name; a.ownerId = metadata.ownerId; a.businessId = metadata.businessId
            a.openedOn = metadata.openedOn; a.status = metadata.status; a.access = metadata.access
            return a
        }
    }

    public static func prepare(state: BusinessSimulationState, accounts: [BankAccount], start: GameDate, end: GameDate,
                               economy: EconomyCard, businessChanges: [BusinessChange] = [],
                               obligationChanges: [ObligationChange] = [], accountChanges: [AccountLifecycleChange] = [],
                               saleProposals: [SaleProposal] = [], revision: Int) throws -> Plan {
        var plan = Plan(state: state, accounts: accounts)
        guard end >= start, end.daysSince(start) <= 366_000 else { throw ValidationError.invalid("Business settlement dates are invalid.") }
        guard businessChanges.count <= 20, obligationChanges.count <= 100, accountChanges.count <= 20, saleProposals.count <= 10 else {
            plan.rejections.append("Too many business changes in one turn."); return plan
        }
        for change in businessChanges {
            do { try apply(change, start: start, end: end, economy: economy, to: &plan) }
            catch { plan.rejections.append("business_changes \(change.id): \(error.localizedDescription)") }
        }
        for change in obligationChanges {
            do { try apply(change, start: start, end: end, economy: economy, to: &plan) }
            catch { plan.rejections.append("obligation_changes \(change.id): \(error.localizedDescription)") }
        }
        for change in accountChanges {
            do {
                let date = try effective(change.effectiveFrom, start: start, end: end)
                guard !plan.state.pendingAccountChanges.contains(change) else { throw invalid("This account change is already scheduled.") }
                if date == start { try applyAccountChange(change, date: date, to: &plan) }
                else { plan.state.pendingAccountChanges.append(change) }
            } catch { plan.rejections.append("account_lifecycle \(change.accountId): \(error.localizedDescription)") }
        }
        for proposal in saleProposals {
            do { try proposeSale(proposal, start: start, end: end, economy: economy, revision: revision, to: &plan) }
            catch { plan.rejections.append("sale_proposals \(proposal.id): \(error.localizedDescription)") }
        }
        syncMetadata(&plan)
        return plan
    }

    public static func plan(state: BusinessSimulationState, accounts: [BankAccount], start: GameDate, end: GameDate,
                            economy: EconomyCard, businessChanges: [BusinessChange] = [],
                            obligationChanges: [ObligationChange] = [], accountChanges: [AccountLifecycleChange] = [],
                            saleProposals: [SaleProposal] = [], revision: Int) throws -> Plan {
        let prepared = try prepare(state: state, accounts: accounts, start: start, end: end, economy: economy,
            businessChanges: businessChanges, obligationChanges: obligationChanges, accountChanges: accountChanges,
            saleProposals: saleProposals, revision: revision)
        guard prepared.rejections.isEmpty else { return prepared }
        var settled = try settle(state: prepared.state, accounts: prepared.accounts, from: start, to: end, economy: economy)
        settled.ledger = prepared.ledger + settled.ledger
        settled.accountOpenings = prepared.accountOpenings + settled.accountOpenings
        return settled
    }

    static func apply(_ change: BusinessChange, start: GameDate, end: GameDate, economy: EconomyCard, to plan: inout Plan) throws {
        try identifier(change.id)
        let date = try effective(change.effectiveFrom, start: start, end: end)
        let index = plan.state.businesses.firstIndex { $0.id == change.id }
        switch change.action {
        case .create:
            guard index == nil, plan.state.businesses.count < 200, let name = change.name,
                  let accountId = change.accountId, let jurisdiction = change.jurisdiction else {
                throw invalid("A new business needs a unique ID, name, account and preset jurisdiction.")
            }
            try label(name); try identifier(accountId)
            _ = try profile(jurisdiction, on: date, economy: economy, state: plan.state)
            guard (0...1_000_000_000_000).contains(change.costBasisMinor ?? 0) else { throw invalid("Cost basis is outside the supported range.") }
            if let a = plan.accounts.firstIndex(where: { $0.id == accountId }) {
                guard plan.accounts[a].isAccessible, plan.accounts[a].kind == .business,
                      plan.accounts[a].businessId == nil else { throw invalid("The operating account must be an accessible, unassigned business account.") }
                plan.accounts[a].businessId = change.id; plan.accounts[a].ownerId = change.id
            } else {
                guard name.count <= 100, !plan.accounts.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw invalid("The new operating account needs a unique name of at most 100 characters, including against closed-account names.")
                }
                plan.accounts.append(BankAccount(id: accountId, name: name, kind: .business, ownerId: change.id,
                                                 businessId: change.id, openedOn: date))
                plan.accountOpenings.append(AccountOpening(id: accountId, name: name, kind: .business))
            }
            plan.state.businesses.append(BusinessRecord(id: change.id, name: name, accountId: accountId,
                jurisdiction: jurisdiction, legalStructure: change.legalStructure ?? .incorporated,
                openedOn: date, costBasisMinor: change.costBasisMinor ?? 0))
        case .update:
            guard let index, plan.state.businesses[index].status == .active else { throw invalid("The business is not active and owned.") }
            guard change.accountId == nil || change.accountId == plan.state.businesses[index].accountId,
                  change.legalStructure == nil || change.legalStructure == plan.state.businesses[index].legalStructure,
                  change.costBasisMinor == nil || change.costBasisMinor == plan.state.businesses[index].costBasisMinor else {
                throw invalid("Changing an established business's structure, account or cost basis requires a new business record; historical accounting cannot be rewritten.")
            }
            if let jurisdiction = change.jurisdiction {
                _ = try profile(jurisdiction, on: date, economy: economy, state: plan.state)
                plan.state.businesses[index].jurisdictions.removeAll { $0.effectiveFrom == date }
                plan.state.businesses[index].jurisdictions.append(BusinessJurisdictionPeriod(jurisdiction: jurisdiction, effectiveFrom: date))
                plan.state.businesses[index].jurisdiction = jurisdiction
            }
            if let name = change.name { try label(name); plan.state.businesses[index].name = name }
        case .end:
            guard let index, plan.state.businesses[index].status == .active else { throw invalid("The business is not active and owned.") }
            plan.state.businesses[index].endedOn = date
            for i in plan.state.obligations.indices where plan.state.obligations[i].businessId == change.id && (plan.state.obligations[i].endedOn == nil || plan.state.obligations[i].endedOn! > date) {
                plan.state.obligations[i].endedOn = date
            }
        }
    }

    static func apply(_ change: ObligationChange, start: GameDate, end: GameDate, economy: EconomyCard, to plan: inout Plan) throws {
        try identifier(change.id)
        let date = try effective(change.effectiveFrom, start: start, end: end)
        let priorIndex = plan.state.obligations.lastIndex { $0.id == change.id && $0.effectiveFrom <= date && ($0.endedOn == nil || date < $0.endedOn!) }
        if change.action == .end {
            guard let priorIndex else { throw invalid("There is no active obligation with this ID.") }
            plan.state.obligations[priorIndex].endedOn = date; return
        }
        if change.action == .start && plan.state.obligations.contains(where: { $0.id == change.id }) { throw invalid("Use change for an existing obligation ID.") }
        if change.action == .change && priorIndex == nil { throw invalid("There is no active obligation to change.") }
        let prior = priorIndex.map { plan.state.obligations[$0] }
        guard let businessId = change.businessId ?? prior?.businessId,
              let business = plan.state.businesses.first(where: { $0.id == businessId }), active(business, on: date),
              let kind = change.kind ?? prior?.kind, let name = change.name ?? prior?.name,
              let amount = change.monthlyMinor ?? prior?.monthlyMinor, (1...1_000_000_000_000).contains(amount) else {
            throw invalid("A recurring record needs an active business, kind, name, and explicit positive monthly amount.")
        }
        try label(name)
        if kind == .ownerSalary && business.legalStructure == .soleProprietor {
            throw invalid("A sole proprietor takes owner draws through transfers; profits are taxed directly instead of deducting an owner salary.")
        }
        let headcount = change.headcount ?? prior?.headcount ?? 1
        guard (1...100_000).contains(headcount), kind == .payroll || headcount == 1 else { throw invalid("Only employee payroll can have multiple employees.") }
        _ = try multiply(amount, Int64(headcount))
        guard prior == nil || headcount <= prior!.headcount else {
            throw invalid("Keep the existing payroll group for continuing employees and create a separate group for new hires, so new employees do not inherit used annual caps.")
        }
        let from = change.fromAccountId ?? prior?.fromAccountId ?? business.accountId
        guard let account = plan.accounts.first(where: { $0.id == from }), account.isAccessible,
              account.businessId == businessId, account.kind != .taxReserve else { throw invalid("The source must be an accessible account belonging to this business.") }
        let to = change.toAccountId ?? prior?.toAccountId ?? (kind == .ownerSalary ? plan.state.defaultPersonalAccountId : nil)
        if let to {
            guard to != from, let target = plan.accounts.first(where: { $0.id == to }), target.isAccessible else { throw invalid("The destination must be another accessible account.") }
            if kind == .ownerSalary && (target.businessId != nil || target.kind != .personal) { throw invalid("Owner salary must go to an accessible personal account.") }
        }
        guard kind != .transfer || to != nil else { throw invalid("A scheduled transfer needs a destination account.") }
        let jurisdiction = change.jurisdiction ?? prior?.jurisdiction
        let rules = try profile(jurisdiction ?? business.jurisdiction(on: date), on: date, economy: economy, state: plan.state)
        let taxResidence = change.taxResidence ?? prior?.taxResidence
        if kind == .ownerSalary && taxResidence == nil { throw invalid("Owner salary needs the owner's preset tax residence; the company's location is not automatically the owner's residence.") }
        if let taxResidence { _ = try profile(taxResidence, on: date, economy: economy, state: plan.state) }
        let birthDate = change.employeeBirthDate.flatMap(GameDate.init(iso:)) ?? prior?.employeeBirthDate
        if change.employeeBirthDate != nil && birthDate == nil { throw invalid("Employee birth date must be a valid calendar date.") }
        let hours = change.monthlyHours ?? prior?.monthlyHours
        if let hours, !(1...744).contains(hours) { throw invalid("Monthly work hours must be between 1 and 744.") }
        if kind == .payroll {
            if let birthDate, date.ageYears(bornOn: birthDate) < rules.minimumEmploymentAge { throw invalid("The recorded employee is below this jurisdiction's employment age.") }
            if let hours, amount < (try multiply(rules.minimumHourlyWageMinor, Int64(hours))) { throw invalid("The gross pay is below the preset minimum for the recorded monthly work hours.") }
        }
        if let priorIndex { plan.state.obligations[priorIndex].endedOn = date }
        plan.state.obligations.append(RecurringObligation(id: change.id, businessId: businessId, kind: kind,
            name: name, monthlyMinor: amount, headcount: headcount, fromAccountId: from,
            toAccountId: to, jurisdiction: jurisdiction, taxResidence: taxResidence,
            employeeBirthDate: birthDate, monthlyHours: hours, effectiveFrom: date))
        if change.toAccountId != nil, date == start, let current = plan.state.obligations.last {
            rerouteBlockedPayments(for: current, on: date, to: &plan)
        }
    }

    static func applyAccountChange(_ change: AccountLifecycleChange, date: GameDate, to plan: inout Plan) throws {
        guard let index = plan.accounts.firstIndex(where: { $0.id == change.accountId }), plan.accounts[index].isAccessible else {
            throw invalid("This account is closed, transferred, restricted, or unknown.")
        }
        switch change.action {
        case .rename:
            guard let name = change.name else { throw invalid("Enter an account name.") }
            try label(name)
            guard name.count <= 100, !plan.accounts.contains(where: { $0.id != change.accountId && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw invalid("Account names must be unique, including closed accounts, and at most 100 characters.")
            }
            plan.accounts[index].name = name
        case .setDefault:
            guard plan.accounts[index].kind == .personal, plan.accounts[index].businessId == nil else { throw invalid("The default account must be personal.") }
            plan.state.defaultPersonalAccountId = change.accountId
        case .close:
            guard !plan.state.businesses.contains(where: { $0.accountId == change.accountId && active($0, on: date) }),
                  !plan.state.obligations.contains(where: { ($0.fromAccountId == change.accountId || $0.toAccountId == change.accountId) && ($0.endedOn == nil || $0.endedOn! > date) }),
                  !plan.state.accruals.contains(where: { $0.obligation.fromAccountId == change.accountId || $0.obligation.toAccountId == change.accountId }),
                  !plan.state.payables.contains(where: { ($0.fromAccountId == change.accountId || $0.toAccountId == change.accountId) && $0.remainingMinor > 0 }) else {
                throw invalid("Resolve the business, recurring obligations, accrued amounts and unpaid bills before closing this account.")
            }
            if plan.state.defaultPersonalAccountId == change.accountId {
                guard let replacement = change.replacementAccountId, replacement != change.accountId,
                      let a = plan.accounts.first(where: { $0.id == replacement }), a.isAccessible, a.kind == .personal, a.businessId == nil else {
                    throw invalid("Choose a different accessible personal account as the default before closing this one.")
                }
            }
            let balance = plan.accounts[index].balanceMinor
            if balance > 0 {
                guard let destination = change.balanceDestinationAccountId, destination != change.accountId,
                      plan.accounts.contains(where: { $0.id == destination && $0.isAccessible }) else {
                    throw invalid("Choose an accessible destination for the remaining balance.")
                }
                try post(-balance, source: .transfer, account: change.accountId, date: date, reason: "Account closure transfer", to: &plan)
                try post(balance, source: .transfer, account: destination, date: date, reason: "Account closure transfer", to: &plan)
            }
            if plan.state.defaultPersonalAccountId == change.accountId { plan.state.defaultPersonalAccountId = change.replacementAccountId! }
            plan.accounts[index].status = .closed; plan.accounts[index].access = .none
        }
    }

    static func active(_ business: BusinessRecord, on date: GameDate) -> Bool {
        business.openedOn <= date && (business.endedOn == nil || date < business.endedOn!) && business.status != .sold
    }
    static func effective(_ value: String?, start: GameDate, end: GameDate) throws -> GameDate {
        let parsed: GameDate? = value == nil ? start : GameDate(iso: value!)
        guard let date = parsed, date >= start, date <= end else {
            throw invalid("The effective date must be a valid date within this turn; historical money cannot be backfilled.")
        }
        return date
    }
    static func identifier(_ value: String) throws {
        guard !value.isEmpty, value.count <= 100, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }), !value.hasPrefix("_engine_") else {
            throw invalid("Use a stable ID of letters, digits, hyphens or underscores (maximum 100 characters).")
        }
    }
    static func label(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 200 else { throw invalid("A nonempty name of at most 200 characters is required.") }
    }
    static func profile(_ jurisdiction: JurisdictionRef, on date: GameDate, economy: EconomyCard, state: BusinessSimulationState? = nil) throws -> FiscalProfile {
        let values = state?.fiscalOverrides.filter {
            $0.jurisdiction.countryID == jurisdiction.countryID && $0.jurisdiction.subdivisionID == jurisdiction.subdivisionID && $0.effectiveFrom <= date
        }.sorted { $0.effectiveFrom < $1.effectiveFrom }.last?.values
        return try FiscalRuleResolver.resolve(jurisdiction: jurisdiction, on: date, accountingCurrency: economy.currency,
                                               minorUnitsPerUnit: economy.minorUnitsPerUnit, overrides: values)
    }
    static func fiscalYear(on date: GameDate, profile: FiscalProfile) -> Int {
        max(1, (date.month, date.day) < (profile.taxYearStartMonth, profile.taxYearStartDay) ? date.year - 1 : date.year)
    }
    public static func applyingFiscalOverride(_ change: BusinessFiscalOverride, to state: BusinessSimulationState,
                                               at date: GameDate, economy: EconomyCard) throws -> BusinessSimulationState {
        guard change.effectiveFrom == date else { throw invalid("Fiscal overrides start today; recorded assessments are never recalculated.") }
        try change.values.validate()
        _ = try FiscalRuleResolver.resolve(jurisdiction: change.jurisdiction, on: date,
            accountingCurrency: economy.currency, minorUnitsPerUnit: economy.minorUnitsPerUnit, overrides: change.values)
        var updated = state
        updated.fiscalOverrides.removeAll { $0.jurisdiction.countryID == change.jurisdiction.countryID && $0.jurisdiction.subdivisionID == change.jurisdiction.subdivisionID && $0.effectiveFrom == date }
        updated.fiscalOverrides.append(change)
        return updated
    }
    static func multiply(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (n, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw invalid("Business amount is outside the supported range.") }; return n
    }
    static func invalid(_ text: String) -> ValidationError { .invalid(text) }
    static func syncMetadata(_ plan: inout Plan) { plan.state.accountMetadata = plan.accounts.map(BusinessAccountMetadata.init(account:)) }
    static func post(_ amount: Int64, source: SourceType, account: String, date: GameDate, reason: String, to plan: inout Plan) throws {
        guard let i = plan.accounts.firstIndex(where: { $0.id == account }), plan.accounts[i].status == .active else { throw invalid("The settlement account is unavailable: \(account).") }
        let balance = try CheckedMoney.add(plan.accounts[i].balanceMinor, amount)
        guard balance >= 0 else { throw invalid("The business cannot spend unrecorded money.") }
        guard amount != 0 else { return }
        plan.accounts[i].balanceMinor = balance
        plan.ledger.append(NewLedgerEntry(date: date, sourceType: source, amountMinor: amount, reason: reason,
                                         counterparty: nil, origin: .engine, accountId: account))
    }
}
