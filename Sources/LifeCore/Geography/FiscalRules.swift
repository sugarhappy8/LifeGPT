import Foundation

public enum RuleStatus: String, Codable, Sendable { case sourced, estimated, notApplicable }
public enum FiscalFactor: String, Codable, CaseIterable, Sendable {
    case incomeTax, personalAllowance, employeeSocial, employerContributions, businessTax, capitalGains
    case transactionTax, taxCalendar, currencyExchange, wages, livingCosts, minimumWage, employmentAge, accountAge, regionalTax
}
public struct RuleEvidence: Codable, Hashable, Sendable {
    public let status: RuleStatus
    public let explanation: String
    public let sources: [String]
    public let effectiveFrom: String
    public let effectiveUntil: String
    public init(status: RuleStatus, explanation: String, sources: [String] = [], effectiveFrom: String, effectiveUntil: String) {
        self.status = status; self.explanation = explanation; self.sources = sources; self.effectiveFrom = effectiveFrom; self.effectiveUntil = effectiveUntil
    }
}
public struct TaxBracket: Codable, Hashable, Sendable {
    /// Cumulative upper bound in this life's accounting minor units. Nil means unlimited.
    public let upToMinor: Int64?
    public let rateBasisPoints: Int
    public init(upToMinor: Int64?, rateBasisPoints: Int) { self.upToMinor = upToMinor; self.rateBasisPoints = rateBasisPoints }
}
public struct PayrollContribution: Codable, Hashable, Sendable {
    public let name: String
    public let rateBasisPoints: Int
    public let annualCapMinor: Int64?
    public init(name: String, rateBasisPoints: Int, annualCapMinor: Int64? = nil) {
        self.name = name; self.rateBasisPoints = rateBasisPoints; self.annualCapMinor = annualCapMinor
    }
}
public struct CurrencyConversionAssumption: Codable, Hashable, Sendable {
    public let date: GameDate
    public let fromCurrency: String
    public let toCurrency: String
    public let accountingUnitsPerLocalUnit: Double
    public let status: RuleStatus
    public let explanation: String
}
/// Only user-editable assumptions; overrides can never manufacture sourced evidence.
public struct FiscalOverrides: Codable, Hashable, Sendable {
    public var incomeTaxBasisPoints: Int?
    public var employeeSocialBasisPoints: Int?
    public var employerContributionBasisPoints: Int?
    public var businessTaxBasisPoints: Int?
    public var capitalGainsBasisPoints: Int?
    public var annualAllowanceMinor: Int64?
    public var minimumHourlyWageMinor: Int64?
    public var minimumEmploymentAge: Int?
    public var independentAccountAge: Int?
    public var accountingUnitsPerLocalUnit: Double?
    public init(incomeTaxBasisPoints: Int? = nil, employeeSocialBasisPoints: Int? = nil, employerContributionBasisPoints: Int? = nil,
                businessTaxBasisPoints: Int? = nil, capitalGainsBasisPoints: Int? = nil, annualAllowanceMinor: Int64? = nil,
                minimumHourlyWageMinor: Int64? = nil, minimumEmploymentAge: Int? = nil, independentAccountAge: Int? = nil,
                accountingUnitsPerLocalUnit: Double? = nil) {
        self.incomeTaxBasisPoints = incomeTaxBasisPoints; self.employeeSocialBasisPoints = employeeSocialBasisPoints
        self.employerContributionBasisPoints = employerContributionBasisPoints; self.businessTaxBasisPoints = businessTaxBasisPoints
        self.capitalGainsBasisPoints = capitalGainsBasisPoints; self.annualAllowanceMinor = annualAllowanceMinor
        self.minimumHourlyWageMinor = minimumHourlyWageMinor; self.minimumEmploymentAge = minimumEmploymentAge
        self.independentAccountAge = independentAccountAge; self.accountingUnitsPerLocalUnit = accountingUnitsPerLocalUnit
    }
    public func validate() throws {
        for rate in [incomeTaxBasisPoints, employeeSocialBasisPoints, employerContributionBasisPoints, businessTaxBasisPoints, capitalGainsBasisPoints].compactMap({ $0 }) {
            guard (0...10_000).contains(rate) else { throw ValidationError.invalid("Tax/contribution estimates must be between 0% and 100%.") }
        }
        for value in [annualAllowanceMinor, minimumHourlyWageMinor].compactMap({ $0 }) {
            guard (0...1_000_000_000_000_000).contains(value) else { throw ValidationError.invalid("Fiscal amounts are outside the supported range.") }
        }
        for age in [minimumEmploymentAge, independentAccountAge].compactMap({ $0 }) {
            guard (0...100).contains(age) else { throw ValidationError.invalid("Fiscal eligibility ages must be between 0 and 100.") }
        }
        if let fx = accountingUnitsPerLocalUnit, !fx.isFinite || fx <= 0 || fx > 1_000_000_000 {
            throw ValidationError.invalid("The exchange-rate assumption must be finite and positive.")
        }
    }
}
public struct PayrollCalculation: Codable, Hashable, Sendable {
    public let grossMinor: Int64
    public let incomeTaxMinor: Int64
    public let employeeSocialMinor: Int64
    public let employerContributionMinor: Int64
    public let netMinor: Int64
    public var totalEmployerCostMinor: Int64 { grossMinor + employerContributionMinor }
}

/// A dated immutable snapshot. Keep this with payments; updates must not rewrite past calculations.
public struct FiscalProfile: Codable, Hashable, Sendable {
    public let jurisdiction: JurisdictionRef
    public let date: GameDate
    public let version: String
    public let accountingCurrency: String
    public let minorUnitsPerUnit: Int
    public let localCurrency: String
    public let conversion: CurrencyConversionAssumption
    public let provenance: [FiscalFactor: RuleEvidence]
    public let incomeBrackets: [TaxBracket]
    public let annualAllowanceMinor: Int64
    public let employeeContributions: [PayrollContribution]
    public let employerContributions: [PayrollContribution]
    public let businessBrackets: [TaxBracket]
    public let capitalGainBrackets: [TaxBracket]
    public let transactionTaxBasisPoints: Int
    public let regionalIncomeTaxBasisPoints: Int
    public let regionalBusinessTaxBasisPoints: Int
    public let minimumHourlyWageMinor: Int64
    public let minimumEmploymentAge: Int
    public let independentAccountAge: Int
    public let taxYearStartMonth: Int
    public let taxYearStartDay: Int
    public let assumptions: [String]
    /// Personal payroll/capital-gains year. Incorporated businesses separately elect calendar accounting by default.
    public func taxYearStart(for day: GameDate) -> GameDate {
        if day.year == 1, (day.month, day.day) < (taxYearStartMonth, taxYearStartDay) { return GameDate(year: 1, month: 1, day: 1) }
        let year = (day.month, day.day) < (taxYearStartMonth, taxYearStartDay) ? day.year - 1 : day.year
        return GameDate(year: year, month: taxYearStartMonth, day: taxYearStartDay)
    }
    public var hasEstimates: Bool { provenance.values.contains { $0.status == .estimated } }
    public var summary: String {
        let estimates = FiscalFactor.allCases.filter { provenance[$0]?.status == .estimated }.map(\.rawValue).joined(separator: ", ")
        return "\(CountryCatalog.shared.displayName(jurisdiction)) · \(date.iso) · rules \(version) · \(localCurrency) → \(accountingCurrency). Estimates: \(estimates). " + assumptions.joined(separator: " ")
    }
    /// Inputs are per person. Output totals multiply only after applying each person's annual cap and allowance.
    public func calculatePayroll(grossMinor: Int64, yearToDateGrossMinor: Int64 = 0, employeeCount: Int = 1) throws -> PayrollCalculation {
        try Self.check(grossMinor, yearToDateGrossMinor)
        guard (1...100_000).contains(employeeCount) else { throw ValidationError.invalid("Payroll headcount must be between 1 and 100,000.") }
        let after = grossMinor + yearToDateGrossMinor
        let taxableBefore = max(0, yearToDateGrossMinor - annualAllowanceMinor), taxableAfter = max(0, after - annualAllowanceMinor)
        let national = try Self.tax(taxableAfter, incomeBrackets) - Self.tax(taxableBefore, incomeBrackets)
        let regional = try Self.rate(taxableAfter, regionalIncomeTaxBasisPoints) - Self.rate(taxableBefore, regionalIncomeTaxBasisPoints)
        let social = try contributions(employeeContributions, before: yearToDateGrossMinor, after: after)
        let employer = try contributions(employerContributions, before: yearToDateGrossMinor, after: after)
        let employeeSocial = min(grossMinor, social)
        let incomeTax = min(grossMinor - employeeSocial, max(0, national + regional))
        let totalGross = try Self.multiply(grossMinor, employeeCount)
        let totalEmployer = try Self.multiply(employer, employeeCount)
        guard totalGross <= Int64.max - totalEmployer else { throw ValidationError.invalid("Payroll total is too large.") }
        return PayrollCalculation(grossMinor: totalGross, incomeTaxMinor: try Self.multiply(incomeTax, employeeCount),
            employeeSocialMinor: try Self.multiply(employeeSocial, employeeCount), employerContributionMinor: totalEmployer,
            netMinor: try Self.multiply(grossMinor - incomeTax - employeeSocial, employeeCount))
    }
    public func businessTax(taxableProfitMinor: Int64, yearToDateProfitMinor: Int64 = 0) throws -> Int64 {
        try Self.check(taxableProfitMinor, yearToDateProfitMinor)
        let after = yearToDateProfitMinor + taxableProfitMinor
        return try Self.tax(after, businessBrackets) - Self.tax(yearToDateProfitMinor, businessBrackets)
            + Self.rate(after, regionalBusinessTaxBasisPoints) - Self.rate(yearToDateProfitMinor, regionalBusinessTaxBasisPoints)
    }
    public func capitalGainsTax(gainMinor: Int64, yearToDateGainMinor: Int64 = 0) throws -> Int64 {
        try Self.check(gainMinor, yearToDateGainMinor)
        return try Self.tax(gainMinor + yearToDateGainMinor, capitalGainBrackets) - Self.tax(yearToDateGainMinor, capitalGainBrackets)
    }
    /// Call only for explicitly taxable receipts, never for every deposit or transfer.
    public func transactionTax(taxableAmountMinor: Int64) throws -> Int64 {
        try Self.check(taxableAmountMinor, 0)
        return try Self.rate(taxableAmountMinor, transactionTaxBasisPoints)
    }
    private func contributions(_ rules: [PayrollContribution], before: Int64, after: Int64) throws -> Int64 {
        try rules.reduce(Int64(0)) { sum, rule in
            let cappedBefore = min(before, rule.annualCapMinor ?? Int64.max), cappedAfter = min(after, rule.annualCapMinor ?? Int64.max)
            return try sum + Self.rate(cappedAfter, rule.rateBasisPoints) - Self.rate(cappedBefore, rule.rateBasisPoints)
        }
    }
    private static func check(_ a: Int64, _ b: Int64) throws {
        guard (0...1_000_000_000_000_000).contains(a), (0...1_000_000_000_000_000).contains(b) else { throw ValidationError.invalid("Fiscal calculations need nonnegative supported money amounts.") }
    }
    private static func multiply(_ a: Int64, _ b: Int) throws -> Int64 {
        let (result, overflow) = a.multipliedReportingOverflow(by: Int64(b))
        guard !overflow else { throw ValidationError.invalid("Payroll total is too large.") }; return result
    }
    static func rate(_ amount: Int64, _ basis: Int) throws -> Int64 {
        try rounded(Decimal(amount) * Decimal(basis) / 10_000)
    }
    static func rounded(_ value: Decimal) throws -> Int64 {
        var value = value, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard !rounded.isNaN, rounded >= 0, rounded <= Decimal(Int64.max) else { throw ValidationError.invalid("Fiscal amount is outside the supported range.") }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
    private static func tax(_ amount: Int64, _ brackets: [TaxBracket]) throws -> Int64 {
        var low: Int64 = 0, tax: Decimal = 0
        for bracket in brackets {
            let high = bracket.upToMinor ?? amount
            let portion = max(0, min(amount, high) - low)
            tax += Decimal(portion) * Decimal(bracket.rateBasisPoints) / 10_000
            low = high
            if amount <= high { break }
        }
        return try rounded(tax)
    }
}
