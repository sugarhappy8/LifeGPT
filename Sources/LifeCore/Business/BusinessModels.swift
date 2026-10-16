import Foundation

public struct BusinessRecord: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case active, ended, sold }
    public enum LegalStructure: String, Codable, CaseIterable, Sendable { case incorporated, soleProprietor = "sole_proprietor" }
    public var id: String
    public var name: String
    public var accountId: String
    public var jurisdiction: JurisdictionRef
    public var legalStructure: LegalStructure
    public var openedOn: GameDate
    public var endedOn: GameDate?
    public var status: Status
    public var costBasisMinor: Int64
    public var jurisdictions: [BusinessJurisdictionPeriod]
    public init(id: String, name: String, accountId: String, jurisdiction: JurisdictionRef,
                legalStructure: LegalStructure = .incorporated, openedOn: GameDate,
                endedOn: GameDate? = nil, status: Status = .active, costBasisMinor: Int64 = 0) {
        self.id = id; self.name = name; self.accountId = accountId; self.jurisdiction = jurisdiction
        self.legalStructure = legalStructure; self.openedOn = openedOn; self.endedOn = endedOn
        self.status = status; self.costBasisMinor = costBasisMinor
        self.jurisdictions = [BusinessJurisdictionPeriod(jurisdiction: jurisdiction, effectiveFrom: openedOn)]
    }
    public func jurisdiction(on date: GameDate) -> JurisdictionRef {
        jurisdictions.filter { $0.effectiveFrom <= date }.sorted { $0.effectiveFrom < $1.effectiveFrom }.last?.jurisdiction ?? jurisdiction
    }
}

public struct BusinessJurisdictionPeriod: Codable, Equatable, Sendable {
    public var jurisdiction: JurisdictionRef
    public var effectiveFrom: GameDate
}

/// Versions are immutable intervals. Changing a record closes its previous version.
public struct RecurringObligation: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case revenue, payroll, ownerSalary = "owner_salary", expense, transfer }
    public var id: String
    public var businessId: String
    public var kind: Kind
    public var name: String
    /// Per employee for payroll; total monthly amount for other kinds.
    public var monthlyMinor: Int64
    public var headcount: Int
    public var fromAccountId: String
    public var toAccountId: String?
    public var jurisdiction: JurisdictionRef?
    public var taxResidence: JurisdictionRef?
    public var employeeBirthDate: GameDate?
    public var monthlyHours: Int?
    public var effectiveFrom: GameDate
    public var endedOn: GameDate?
    public init(id: String, businessId: String, kind: Kind, name: String, monthlyMinor: Int64,
                headcount: Int = 1, fromAccountId: String, toAccountId: String? = nil,
                jurisdiction: JurisdictionRef? = nil, taxResidence: JurisdictionRef? = nil,
                employeeBirthDate: GameDate? = nil, monthlyHours: Int? = nil,
                effectiveFrom: GameDate, endedOn: GameDate? = nil) {
        self.id = id; self.businessId = businessId; self.kind = kind; self.name = name
        self.monthlyMinor = monthlyMinor; self.headcount = headcount; self.fromAccountId = fromAccountId
        self.toAccountId = toAccountId; self.jurisdiction = jurisdiction
        self.taxResidence = taxResidence; self.employeeBirthDate = employeeBirthDate; self.monthlyHours = monthlyHours
        self.effectiveFrom = effectiveFrom; self.endedOn = endedOn
    }
}

public struct BusinessChange: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case create, update, end }
    public var action: Action
    public var id: String
    public var name: String?
    public var accountId: String?
    public var jurisdiction: JurisdictionRef?
    public var legalStructure: BusinessRecord.LegalStructure?
    public var effectiveFrom: String?
    public var costBasisMinor: Int64?
    public init(action: Action, id: String, name: String? = nil, accountId: String? = nil,
                jurisdiction: JurisdictionRef? = nil, legalStructure: BusinessRecord.LegalStructure? = nil,
                effectiveFrom: String? = nil, costBasisMinor: Int64? = nil) {
        self.action = action; self.id = id; self.name = name; self.accountId = accountId
        self.jurisdiction = jurisdiction; self.legalStructure = legalStructure
        self.effectiveFrom = effectiveFrom; self.costBasisMinor = costBasisMinor
    }
}

public struct ObligationChange: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case start, change, end }
    public var action: Action
    public var id: String
    public var businessId: String?
    public var kind: RecurringObligation.Kind?
    public var name: String?
    public var monthlyMinor: Int64?
    public var headcount: Int?
    public var fromAccountId: String?
    public var toAccountId: String?
    public var jurisdiction: JurisdictionRef?
    public var taxResidence: JurisdictionRef?
    public var employeeBirthDate: String?
    public var monthlyHours: Int?
    public var effectiveFrom: String?
    public init(action: Action, id: String, businessId: String? = nil, kind: RecurringObligation.Kind? = nil,
                name: String? = nil, monthlyMinor: Int64? = nil, headcount: Int? = nil,
                fromAccountId: String? = nil, toAccountId: String? = nil,
                jurisdiction: JurisdictionRef? = nil, taxResidence: JurisdictionRef? = nil,
                employeeBirthDate: String? = nil, monthlyHours: Int? = nil, effectiveFrom: String? = nil) {
        self.action = action; self.id = id; self.businessId = businessId; self.kind = kind
        self.name = name; self.monthlyMinor = monthlyMinor; self.headcount = headcount
        self.fromAccountId = fromAccountId; self.toAccountId = toAccountId
        self.jurisdiction = jurisdiction; self.effectiveFrom = effectiveFrom
        self.taxResidence = taxResidence; self.employeeBirthDate = employeeBirthDate; self.monthlyHours = monthlyHours
    }
}

public struct AccountLifecycleChange: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case close, rename, setDefault = "set_default" }
    public var action: Action
    public var accountId: String
    public var name: String?
    public var balanceDestinationAccountId: String?
    public var replacementAccountId: String?
    public var effectiveFrom: String?
    public init(action: Action, accountId: String, name: String? = nil,
                balanceDestinationAccountId: String? = nil, replacementAccountId: String? = nil,
                effectiveFrom: String? = nil) {
        self.action = action; self.accountId = accountId; self.name = name
        self.balanceDestinationAccountId = balanceDestinationAccountId
        self.replacementAccountId = replacementAccountId; self.effectiveFrom = effectiveFrom
    }
}

public struct SaleProposal: Codable, Equatable, Sendable, Identifiable {
    // convertFromSnakeCase spells the acronym "Bps", not "BPS".
    private enum CodingKeys: String, CodingKey {
        case id, businessId, buyer, priceMinor, destinationAccountId, effectiveFrom, ownerJurisdiction, retainedLiabilityIds
        case ownershipBPS = "ownershipBps"
    }
    public var id: String
    public var businessId: String
    public var buyer: String
    public var priceMinor: Int64
    public var ownershipBPS: Int
    public var destinationAccountId: String
    public var effectiveFrom: String
    public var ownerJurisdiction: JurisdictionRef?
    public var retainedLiabilityIds: [String]?
    public init(id: String, businessId: String, buyer: String, priceMinor: Int64, ownershipBPS: Int = 10_000,
                destinationAccountId: String = "personal", effectiveFrom: String, ownerJurisdiction: JurisdictionRef? = nil,
                retainedLiabilityIds: [String]? = nil) {
        self.id = id; self.businessId = businessId; self.buyer = buyer; self.priceMinor = priceMinor
        self.ownershipBPS = ownershipBPS; self.destinationAccountId = destinationAccountId
        self.effectiveFrom = effectiveFrom
        self.ownerJurisdiction = ownerJurisdiction
        self.retainedLiabilityIds = retainedLiabilityIds
    }
}

public struct BusinessSaleDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: String { proposal.id }
    public var proposal: SaleProposal
    /// Revision after the turn which saves this draft. A changed save requires a fresh review.
    public var reviewedRevision: Int
    public var estimatedTaxMinor: Int64
    public var transferredAccountIds: [String]
    public var confirmedOn: GameDate?
    public var fiscalProfile: FiscalProfile
    public var assumptions: [String]
}

public struct BusinessAccountMetadata: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var ownerId: String
    public var businessId: String?
    public var openedOn: GameDate?
    public var status: BankAccount.Status
    public var access: BankAccount.Access
    public init(account: BankAccount) {
        id = account.id; name = account.name; ownerId = account.ownerId; businessId = account.businessId
        openedOn = account.openedOn; status = account.status; access = account.access
    }
}

/// Accrual retains a numerator instead of rounding each day/turn, making split skips identical.
public struct BusinessAccrual: Codable, Equatable, Sendable {
    public var obligation: RecurringObligation
    public var businessJurisdiction: JurisdictionRef
    public var ruleDate: GameDate
    public var periodStart: GameDate
    public var numerator: Int64
    public var daysInPeriod: Int
}

public struct BusinessPayable: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case tax, payroll, expense, ownerSalary = "owner_salary", transfer }
    public var id: String
    public var businessId: String
    public var obligationId: String
    public var name: String
    public var kind: Kind
    public var dueOn: GameDate
    public var fromAccountId: String
    public var toAccountId: String?
    public var amountMinor: Int64
    public var paidMinor: Int64
    public var creditedMinor: Int64
    public var refundedMinor: Int64
    /// Payroll deductions are reserved proportionately with gross payments, never minted.
    public var withholdingMinor: Int64
    public var reservedMinor: Int64
    /// Why an unpaid route is blocked, cancelled, or superseded; amounts and old ledger remain intact.
    public var routingIssue: String? = nil
    public var remainingMinor: Int64 { max(0, amountMinor - paidMinor - creditedMinor) }
    public var priority: Int {
        switch kind { case .tax: 0; case .payroll: 1; case .expense, .transfer: 2; case .ownerSalary: 3 }
    }
}

public struct BusinessAssessment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var businessId: String
    public var periodStart: GameDate
    public var periodEnd: GameDate
    public var revenueMinor: Int64
    public var grossPayrollMinor: Int64
    public var employerChargesMinor: Int64
    public var expensesMinor: Int64
    public var taxableProfitMinor: Int64
    public var businessTaxMinor: Int64
    public var profiles: [FiscalProfile]
    public var assumptions: [String]
}

public struct BusinessPayment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var payableId: String
    public var date: GameDate
    public var grossMinor: Int64
    public var withheldMinor: Int64
    public var netMinor: Int64
}

public struct BusinessSimulationState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var businesses: [BusinessRecord] = []
    public var obligations: [RecurringObligation] = []
    public var accruals: [BusinessAccrual] = []
    public var payables: [BusinessPayable] = []
    public var assessments: [BusinessAssessment] = []
    public var payments: [BusinessPayment] = []
    public var accountMetadata: [BusinessAccountMetadata] = []
    public var pendingAccountChanges: [AccountLifecycleChange] = []
    public var saleDrafts: [BusinessSaleDraft] = []
    public var annualPayrollPerPerson: [String: Int64] = [:]
    public var annualBusinessProfit: [String: Int64] = [:]
    public var annualBusinessTaxAssessed: [String: Int64] = [:]
    public var annualCapitalGains: [String: Int64] = [:]
    public var fiscalOverrides: [BusinessFiscalOverride] = []
    public var accruedThrough: GameDate?
    public var defaultPersonalAccountId: String = "personal"
    public init() {}
    public var arrearsMinor: Int64 {
        payables.filter { p in businesses.first(where: { $0.id == p.businessId })?.status != .sold }.reduce(0) {
            let (sum, overflow) = $0.addingReportingOverflow($1.remainingMinor)
            return overflow ? Int64.max : sum
        }
    }
}

public struct BusinessFiscalOverride: Codable, Equatable, Sendable {
    public var jurisdiction: JurisdictionRef
    public var effectiveFrom: GameDate
    public var values: FiscalOverrides
    public init(jurisdiction: JurisdictionRef, effectiveFrom: GameDate, values: FiscalOverrides) {
        self.jurisdiction = jurisdiction; self.effectiveFrom = effectiveFrom; self.values = values
    }
}
