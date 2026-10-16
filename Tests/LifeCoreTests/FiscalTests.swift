import Foundation
import Testing
@testable import LifeCore

@Suite("Dated fiscal profiles and integer payroll")
struct FiscalTests {
    func texas(_ year: Int = 2004, overrides: FiscalOverrides? = nil) throws -> FiscalProfile {
        try FiscalRuleResolver.resolve(jurisdiction: JurisdictionRef(countryID: "US", subdivisionID: "US-TX"),
            on: GameDate(year: year, month: 1, day: 1), accountingCurrency: "USD", minorUnitsPerUnit: 100, overrides: overrides)
    }
    @Test func everyNationResolvesEveryFactorWithHonestProvenance() throws {
        let catalog = CountryCatalog.shared
        for country in catalog.countries {
            let date = GameDate(year: 2024, month: 7, day: 1)
            let currency = country.currency(on: date)
            let ref = JurisdictionRef(countryID: country.id, subdivisionID: country.subdivisionsRequired ? catalog.subdivisions(countryID: country.id).first?.id : nil)
            let profile = try FiscalRuleResolver.resolve(jurisdiction: ref, on: date, accountingCurrency: currency.code, minorUnitsPerUnit: currency.minorUnits)
            #expect(profile.provenance.count == FiscalFactor.allCases.count)
            #expect(profile.provenance.values.allSatisfy { !$0.explanation.isEmpty })
            #expect(profile.provenance.values.filter { $0.status == .sourced }.allSatisfy { !$0.sources.isEmpty })
            #expect(profile.hasEstimates)
            #expect(profile.localCurrency == currency.code)
            let pay = try profile.calculatePayroll(grossMinor: 100_000)
            #expect(pay.grossMinor == pay.netMinor + pay.incomeTaxMinor + pay.employeeSocialMinor)
            #expect(pay.netMinor >= 0)
        }
    }
    @Test func historicalFicaCapsArePerPersonAndYear() throws {
        let profile = try texas()
        let pay = try profile.calculatePayroll(grossMinor: 100_000, yearToDateGrossMinor: 8_790_000, employeeCount: 3)
        #expect(pay.employeeSocialMinor == 4_350) // Medicare only; every person's OASDI cap is already met.
        #expect(pay.grossMinor == 300_000)
        #expect(profile.employeeContributions.first?.annualCapMinor == 8_790_000)
        #expect(try texas(2003).employeeContributions.first?.annualCapMinor == 8_700_000)
        #expect(try texas(2005).employeeContributions.first?.annualCapMinor == 9_000_000)
        #expect(profile.provenance[.employeeSocial]?.status == .sourced)
        #expect(profile.provenance[.employerContributions]?.status == .estimated)
    }
    @Test func salaryCreatesNoMoneyAndCumulativeTaxIsSkipInvariant() throws {
        let profile = try texas()
        let salary = try profile.calculatePayroll(grossMinor: 150_000)
        #expect(salary.grossMinor == 150_000)
        #expect(salary.netMinor == 138_525)
        #expect(salary.totalEmployerCostMinor > salary.grossMinor)
        let annual = try profile.calculatePayroll(grossMinor: 12 * 150_000)
        var income: Int64 = 0, social: Int64 = 0, employer: Int64 = 0
        for month in 0..<12 {
            let p = try profile.calculatePayroll(grossMinor: 150_000, yearToDateGrossMinor: Int64(month) * 150_000)
            income += p.incomeTaxMinor; social += p.employeeSocialMinor; employer += p.employerContributionMinor
        }
        #expect(income == annual.incomeTaxMinor)
        #expect(social == annual.employeeSocialMinor)
        #expect(employer == annual.employerContributionMinor)
    }
    @Test func uaeThresholdUsesAnnualProfitAndExplicitDatedFX() throws {
        let ref = JurisdictionRef(countryID: "AE", subdivisionID: "AE-DU")
        let profile = try FiscalRuleResolver.resolve(jurisdiction: ref, on: GameDate(year: 2024, month: 1, day: 1), accountingCurrency: "AED", minorUnitsPerUnit: 100)
        #expect(try profile.businessTax(taxableProfitMinor: 37_500_000) == 0)
        #expect(try profile.businessTax(taxableProfitMinor: 2_500_000, yearToDateProfitMinor: 37_500_000) == 225_000)
        #expect(profile.provenance[.businessTax]?.status == .sourced)
        #expect(profile.provenance[.employeeSocial]?.status == .estimated)
        #expect(try profile.calculatePayroll(grossMinor: 150_000).incomeTaxMinor == 0)
        let dollars = try FiscalRuleResolver.resolve(jurisdiction: ref, on: profile.date, accountingCurrency: "USD", minorUnitsPerUnit: 100)
        #expect(dollars.accountingCurrency == "USD" && dollars.localCurrency == "AED")
        #expect(dollars.conversion.status == .estimated)
        #expect(abs(dollars.conversion.accountingUnitsPerLocalUnit - 1 / 3.6725) < 0.00001)
        #expect(dollars.businessBrackets.first?.upToMinor != profile.businessBrackets.first?.upToMinor)
    }
    @Test func unsupportedDatesCannotClaimCurrentRulesAreVerified() throws {
        for year in [1800, 2000, 2040] {
            let profile = try FiscalRuleResolver.resolve(jurisdiction: JurisdictionRef(countryID: "AE", subdivisionID: "AE-DU"),
                on: GameDate(year: year, month: 1, day: 1), accountingCurrency: "AED", minorUnitsPerUnit: 100)
            #expect(profile.provenance[.businessTax]?.status == .estimated)
        }
        #expect(try texas(2024).provenance[.employeeSocial]?.status == .estimated)
        let projected = try FiscalRuleResolver.resolve(jurisdiction: JurisdictionRef(countryID: "AE", subdivisionID: "AE-DU"),
            on: GameDate(year: 2040, month: 1, day: 1), accountingCurrency: "AED", minorUnitsPerUnit: 100)
        #expect(projected.businessBrackets.first?.upToMinor == 37_500_000)
        #expect(try projected.businessTax(taxableProfitMinor: 37_500_000) == 0)
        #expect(projected.provenance[.businessTax]?.explanation.contains("Future projection") == true)
    }
    @Test func overridesAreIsolatedValidatedAndNeverBecomeSourced() throws {
        let before = try texas()
        let overridden = try texas(overrides: FiscalOverrides(incomeTaxBasisPoints: 0, employeeSocialBasisPoints: 0, annualAllowanceMinor: 0))
        #expect(overridden.provenance[.employeeSocial]?.status == .estimated)
        #expect(try overridden.calculatePayroll(grossMinor: 150_000).netMinor == 150_000)
        #expect(try texas() == before)
        #expect(throws: (any Error).self) { try texas(overrides: FiscalOverrides(incomeTaxBasisPoints: 10_001)) }
        #expect(throws: (any Error).self) { try texas(overrides: FiscalOverrides(accountingUnitsPerLocalUnit: .nan)) }
        #expect(throws: (any Error).self) { try texas(overrides: FiscalOverrides(accountingUnitsPerLocalUnit: 2)) }
    }
    @Test func personalTaxYearBoundariesAreIndependentOfCalendarBusinessAccounting() throws {
        let before = GameDate(year: 2024, month: 4, day: 5), after = GameDate(year: 2024, month: 4, day: 6)
        let uk = try FiscalRuleResolver.resolve(jurisdiction: JurisdictionRef(countryID: "GB", subdivisionID: "GB-ENG"), on: before, accountingCurrency: "GBP", minorUnitsPerUnit: 100)
        #expect(uk.taxYearStart(for: before) == GameDate(year: 2023, month: 4, day: 6))
        #expect(uk.taxYearStart(for: after) == after)
        #expect(uk.provenance[.taxCalendar]?.explanation.contains("Business accounting is a separate calendar-year election") == true)
        let southAfrica = try FiscalRuleResolver.resolve(jurisdiction: JurisdictionRef(countryID: "ZA"), on: before, accountingCurrency: "ZAR", minorUnitsPerUnit: 100)
        #expect(southAfrica.taxYearStart(for: GameDate(year: 2024, month: 2, day: 29)) == GameDate(year: 2023, month: 3, day: 1))
        #expect(southAfrica.taxYearStart(for: GameDate(year: 2024, month: 3, day: 1)) == GameDate(year: 2024, month: 3, day: 1))
    }
    @Test func missingHistoricCurrencyConversionRequiresAnExplicitAssumption() throws {
        // Andorran pesetas lack a comparable bundled market observation.
        let ref = JurisdictionRef(countryID: "AD")
        let date = GameDate(year: 1950, month: 1, day: 1)
        let local = CountryCatalog.shared.country(id: "AD")!.currency(on: date)
        #expect(CountryCatalog.shared.unobservedCurrencies.contains(local.code))
        do {
            #expect(throws: (any Error).self) { try FiscalRuleResolver.resolve(jurisdiction: ref, on: date, accountingCurrency: "USD", minorUnitsPerUnit: 100) }
            let explicit = try FiscalRuleResolver.resolve(jurisdiction: ref, on: date, accountingCurrency: "USD", minorUnitsPerUnit: 100,
                overrides: FiscalOverrides(accountingUnitsPerLocalUnit: 0.01))
            #expect(explicit.conversion.status == .estimated)
            #expect(explicit.provenance[.wages]?.explanation.contains("neutral one-local-unit") == true)
        }
        let uae = try FiscalRuleResolver.resolve(jurisdiction: JurisdictionRef(countryID: "AE", subdivisionID: "AE-DU"),
            on: GameDate(year: 2023, month: 6, day: 1), accountingCurrency: "AED", minorUnitsPerUnit: 100)
        #expect(uae.provenance[.businessTax]?.effectiveFrom == "2023-06-01")
    }
    @Test func immutableCalculationSnapshotsRoundTrip() throws {
        let profile = try texas()
        let restored = try JSONDecoder().decode(FiscalProfile.self, from: JSONEncoder().encode(profile))
        #expect(restored == profile)
        #expect(restored.version == CountryCatalog.shared.version)
        #expect(try OutputCoding.decoder.decode(FiscalProfile.self, from: OutputCoding.encoder.encode(profile)) == profile)
        #expect(try restored.calculatePayroll(grossMinor: 150_000) == profile.calculatePayroll(grossMinor: 150_000))
    }
    @Test func invalidAmountsAndMissingFXCannotSilentlyCreatePayments() throws {
        let profile = try texas()
        #expect(throws: (any Error).self) { try profile.calculatePayroll(grossMinor: -1) }
        #expect(throws: (any Error).self) { try profile.calculatePayroll(grossMinor: 150_000, employeeCount: 0) }
        #expect(throws: (any Error).self) { try profile.calculatePayroll(grossMinor: 1_000_000_000_000_000, employeeCount: 100_000) }
        #expect(throws: (any Error).self) {
            try FiscalRuleResolver.resolve(jurisdiction: JurisdictionRef(countryID: "FR"), on: profile.date, accountingCurrency: "XYZ", minorUnitsPerUnit: 100)
        }
    }
}
