import Foundation

public enum FiscalRuleResolver {
    public static func resolve(jurisdiction: JurisdictionRef, on date: GameDate, accountingCurrency: String,
                               minorUnitsPerUnit: Int, overrides: FiscalOverrides? = nil) throws -> FiscalProfile {
        let catalog = CountryCatalog.shared
        try catalog.validate(jurisdiction, on: date)
        try overrides?.validate()
        guard !accountingCurrency.isEmpty, accountingCurrency.count <= 12, (1...10_000).contains(minorUnitsPerUnit) else {
            throw ValidationError.invalid("A fiscal profile needs a valid accounting currency and denomination.")
        }
        let country = catalog.country(id: jurisdiction.countryID)!, local = country.currency(on: date)
        let sameCurrency = local.code == accountingCurrency
        if sameCurrency, let override = overrides?.accountingUnitsPerLocalUnit, override != 1 {
            throw ValidationError.invalid("When local and accounting currencies are the same, the conversion must be 1.")
        }
        let localRate = catalog.currencyUnitsPerUSD[local.code], accountingRate = catalog.currencyUnitsPerUSD[accountingCurrency]
        guard sameCurrency || overrides?.accountingUnitsPerLocalUnit != nil || (localRate != nil && accountingRate != nil) else {
            throw ValidationError.invalid("An explicit dated exchange-rate assumption is required for \(local.code) to \(accountingCurrency).")
        }
        if !sameCurrency, overrides?.accountingUnitsPerLocalUnit == nil,
           catalog.unobservedCurrencies.contains(local.code) || catalog.unobservedCurrencies.contains(accountingCurrency) {
            throw ValidationError.invalid("No conversion observation is bundled for this currency pair. Record an explicit dated exchange-rate estimate.")
        }
        let conversion = overrides?.accountingUnitsPerLocalUnit ?? (sameCurrency ? 1 : accountingRate! / localRate!)
        let fxUnknown = catalog.unobservedCurrencies.contains(local.code) || catalog.unobservedCurrencies.contains(accountingCurrency)
        let from = "\(date.year)-01-01", until = "\(date.year)-12-31"
        func evidence(_ text: String, _ status: RuleStatus = .estimated, _ sources: [String] = []) -> RuleEvidence {
            RuleEvidence(status: status, explanation: text, sources: sources, effectiveFrom: from, effectiveUntil: until)
        }
        func localMoney(_ units: Double) throws -> Int64 {
            try FiscalProfile.rounded(Decimal(units) * Decimal(conversion) * Decimal(minorUnitsPerUnit))
        }
        func usdMoney(_ units: Double) throws -> Int64 {
            try localMoney(units * (localRate ?? 1))
        }
        let eraScale = pow(1.025, Double(max(-150, min(100, date.year - catalog.referenceYear))))
        let annualScale = country.annualPerCapitaScaleUSD * eraScale
        let allowance = try usdMoney(annualScale * 0.2)
        var income = [TaxBracket(upToMinor: try usdMoney(annualScale), rateBasisPoints: 1000),
                      TaxBracket(upToMinor: try usdMoney(annualScale * 3), rateBasisPoints: 2000), TaxBracket(upToMinor: nil, rateBasisPoints: 3000)]
        var annualAllowance = allowance
        var employee = [PayrollContribution(name: "Estimated employee social contribution", rateBasisPoints: 500)]
        var employer = [PayrollContribution(name: "Estimated employer contribution", rateBasisPoints: 1000)]
        var business = [TaxBracket(upToMinor: nil, rateBasisPoints: 2500)]
        var capital = [TaxBracket(upToMinor: nil, rateBasisPoints: 1500)]
        var transactionRate = 1000, regionalIncomeRate = country.subdivisionsRequired ? 300 : 0
        var regionalBusinessRate = country.subdivisionsRequired ? 100 : 0
        var minimumWage = try usdMoney(annualScale / 12 * 0.65 * 0.35 / 173.333)
        var minimumAge = 16, accountAge = 18
        var taxYearMonth = 1, taxYearDay = 1
        var assumptions = ["Single resident employee; no dependents, credits, treaty relief or special industry regime assumed.",
                           "Cumulative withholding reserves incremental personal-year liability. Incorporated businesses elect calendar accounting; payment/remittance timing is a simulation estimate.",
                           "Unverified national/regional rates use disclosed simulation estimates; choose per-life overrides for different facts.",
                           catalog.availabilityLabel(countryID: country.id, on: date)]
        let estimate = "\(country.name), \(date.year): local simulation assumption; not a verified statutory rate. National and regional estimates are separate."
        var provenance = Dictionary(uniqueKeysWithValues: FiscalFactor.allCases.map { ($0, evidence(estimate)) })
        provenance[.currencyExchange] = evidence(sameCurrency ? "Accounting currency equals the dated local currency; no conversion." : "Dated conversion estimate from bundled 2024 scale; not a historical market quote." + (fxUnknown ? " Retired currency has no observation; neutral local-unit conversion assumption requires review." : ""), sameCurrency ? .notApplicable : .estimated)
        provenance[.wages] = evidence(catalog.economyAssumptions(for: jurisdiction, on: date) + " Local prices scaled by an estimated 2.5% annual change, bounded for remote eras.")
        provenance[.livingCosts] = evidence("Estimated 55% of the area's modeled median monthly wage; not a US price fallback.")
        provenance[.minimumWage] = evidence("Estimated full-time hourly floor from this area's wage scale; legal coverage and exceptions are unverified.")
        provenance[.employmentAge] = evidence("Estimated ordinary employment age 16; occupation-specific youth restrictions require separate confirmation.")
        provenance[.accountAge] = evidence("Estimated independent-account age 18; younger players require a guardian arrangement.")
        provenance[.taxCalendar] = evidence("Calendar-year accounting and monthly reserves. Actual filing dates, liability settlement and special tax years are not reconstructed.")
        if country.isHistorical || !country.applies(on: date) || date.year < 1974 {
            assumptions.append("Historical area approximation: currencies and predecessor/successor labels are explicit; modern borders are not asserted for this date.")
        }
        if date.year > 2026 { assumptions.append("Projected rules for a future story year; no claim that future legislation is known.") }

        let personalYears: [String: (Int, Int, String)] = [
            "GB": (4, 6, "https://www.gov.uk/government/publications/rates-and-allowances-income-tax/income-tax-rates-and-allowances-current-and-past"),
            "NZ": (4, 1, "https://www.ird.govt.nz/income-tax/income-tax-for-individuals/what-happens-at-the-end-of-the-tax-year/timelines-at-the-end-of-the-tax-year"),
            "AU": (7, 1, "https://my.gov.au/en/services/work/currently-employed/tax-when-you-work/tax-time"),
            "ZA": (3, 1, "https://www.sars.gov.za/about/sars-tax-and-customs-system/"),
            "IN": (4, 1, "https://www.incometax.gov.in/iec/foportal/help/all-topics/e-filing-services/objective-and-scope-new-act-faq")
        ]
        if let period = personalYears[country.id] {
            taxYearMonth = period.0; taxYearDay = period.1
            let temporal = (2024...2026).contains(date.year) ? "Personal-year boundary follows the cited national guidance." : "Historical/future personal-year boundary projected from the current convention; not verified for this era."
            provenance[.taxCalendar] = evidence("Personal income year begins \(period.0)/\(period.1). \(temporal) Business accounting is a separate calendar-year election. Filing and remittance schedules remain estimates.", .estimated, [period.2])
            assumptions.append("Personal income year begins \(period.0)/\(period.1); corporate accounting remains calendar-year unless explicitly modeled otherwise.")
        }

        // Country-specific baseline regimes remain estimates unless a component below cites a verified dated source.
        let zeroWageCountries = Set(["AE", "BH", "KW", "QA", "SA", "OM", "BS", "BM", "KY", "BN", "MC", "TC", "VG", "VU"])
        if zeroWageCountries.contains(country.id) {
            income = [TaxBracket(upToMinor: nil, rateBasisPoints: 0)]; annualAllowance = 0
            regionalIncomeRate = 0
            provenance[.incomeTax] = evidence("Estimated zero employment-income tax for \(country.name) in this scenario; year, residency and special cases remain unverified.")
        }
        let estimatedCorporate: [String: Int] = ["AE":900,"BH":0,"KW":1500,"QA":1000,"SA":2000,"OM":1500,"GB":2500,"IE":1250,"FR":2500,"DE":1500,"JP":2320,"SG":1700,"HK":1650,"CN":2500,"IN":2500,"AU":3000,"NZ":2800,"CA":1500,"CH":850,"BR":2500,"MX":3000,"ZA":2700,"US":2100]
        if let rate = estimatedCorporate[country.id] { business = [TaxBracket(upToMinor: nil, rateBasisPoints: rate)] }
        if ["BS", "BM", "KY", "VG", "TC"].contains(country.id) { business = [TaxBracket(upToMinor: nil, rateBasisPoints: 0)] }

        if country.id == "US", (2003...2005).contains(date.year), country.applies(on: date) {
            let ssCap: Double = [2003:87_000, 2004:87_900, 2005:90_000][date.year]!
            let fica = [PayrollContribution(name: "Social Security", rateBasisPoints: 620, annualCapMinor: try usdMoney(ssCap)),
                        PayrollContribution(name: "Medicare", rateBasisPoints: 145)]
            employee = fica
            // Unemployment/workers compensation depend on employer history: retained as explicit estimate.
            employer = fica + [PayrollContribution(name: "Estimated unemployment/insurance provision", rateBasisPoints: 100, annualCapMinor: try usdMoney(9_000))]
            provenance[.employeeSocial] = evidence("FICA: 6.2% Social Security up to the annual wage base plus uncapped 1.45% Medicare, per employee.", .sourced,
                ["https://www.ssa.gov/oact/cola/cbb.html", "https://www.irs.gov/pub/irs-prior/p15--\(date.year).pdf"])
            provenance[.employerContributions] = evidence("Employer FICA mirrors sourced employee rates. Additional 1% up to $9,000 is an unverified unemployment/insurance provision, not a statutory combined rate.", .estimated,
                ["https://www.irs.gov/pub/irs-prior/p15--\(date.year).pdf"])
            let limits: [Double] = date.year == 2003 ? [7_000,28_400,68_800,143_500,311_950] : date.year == 2004 ? [7_150,29_050,70_350,146_750,319_100] : [7_300,29_700,71_950,150_150,326_450]
            let rates = [1000,1500,2500,2800,3300,3500]
            income = try limits.enumerated().map { TaxBracket(upToMinor: try usdMoney($0.element), rateBasisPoints: rates[$0.offset]) } + [TaxBracket(upToMinor: nil, rateBasisPoints: 3500)]
            annualAllowance = try usdMoney([2003:7_800.0,2004:7_950,2005:8_200][date.year]!)
            provenance[.incomeTax] = evidence("Single-filer federal brackets from the year's IRS publication. Withholding is estimated: AMT, credits, exemption phase-outs and exact payroll tables are not modeled.", .estimated,
                ["https://www.irs.gov/pub/irs-prior/p17--\(date.year).pdf"])
            provenance[.personalAllowance] = evidence("Single standard deduction plus one personal exemption; no dependent claim assumed. High-income phase-outs are not modeled.", .estimated,
                ["https://www.irs.gov/pub/irs-prior/p17--\(date.year).pdf"])
            business = [TaxBracket(upToMinor: nil, rateBasisPoints: 3000)]
            provenance[.businessTax] = evidence("Estimated 30% federal corporation provision; historical graduated corporate tax and special adjustments are not fully implemented.")
            minimumWage = try usdMoney(5.15)
            provenance[.minimumWage] = evidence("Federal floor $5.15/hour for covered, nonexempt workers in this period. Special coverage and state/local exceptions may apply.", .sourced,
                ["https://www.dol.gov/agencies/whd/minimum-wage/history/chart"])
            if jurisdiction.subdivisionID == "US-TX" {
                regionalIncomeRate = 0; regionalBusinessRate = 450
                provenance[.regionalTax] = evidence("Texas personal income component is zero. Corporate franchise provision is an estimated 4.5% of modeled profit; historical taxable-capital alternatives, credits and nexus rules are not reconstructed.", .estimated,
                    ["https://comptroller.texas.gov/taxes/franchise/forms/2007-franchise.php"])
            }
        }
        if country.id == "AE", date.iso >= "2023-06-01" {
            income = [TaxBracket(upToMinor: nil, rateBasisPoints: 0)]; annualAllowance = 0
            business = [TaxBracket(upToMinor: try localMoney(375_000), rateBasisPoints: 0), TaxBracket(upToMinor: nil, rateBasisPoints: 900)]
            regionalIncomeRate = 0; regionalBusinessRate = 0; transactionRate = 500
            capital = [TaxBracket(upToMinor: nil, rateBasisPoints: 0)]
            employee = [PayrollContribution(name: "Estimated UAE-national pension contribution", rateBasisPoints: 1100)]
            employer = [PayrollContribution(name: "Estimated UAE-national employer pension provision", rateBasisPoints: 1500)]
            assumptions.append("Ordinary UAE mainland corporation with a tax period beginning on/after 1 June 2023. Not a qualifying free-zone person or multinational minimum-tax case.")
            assumptions.append("Pension defaults to estimated UAE-national terms; citizenship, first registration, emirate fund and salary caps must be confirmed. Override for expatriate/GCC arrangements.")
            provenance[.incomeTax] = evidence("Wages are excluded from UAE corporate-tax business income.", .sourced,
                ["https://tax.gov.ae/en/taxes/corporate.tax/corporate.tax.topics/basis.of.taxation.natural.person.aspx"])
            provenance[.businessTax] = evidence("Ordinary mainland corporate rate: 0% through AED375,000 annual taxable profit, 9% above. Profile assumes a qualifying tax period and excludes special regimes.", .sourced,
                ["https://www.tax.gov.ae/DataFolder/Files/Guides/CT/CT%20General%20Guide%20-%20EN%20-%2010%2009%202023.pdf"])
            provenance[.employeeSocial] = evidence("Estimated 11% UAE-national pension treatment; nationality, law applicability and salary caps are not established.", .estimated,
                ["https://www.gpssa.gov.ae/pages/en/media-center/news/gpssa-insureds-contribution-payment-may-be-extended-15th-day-each-month"])
            provenance[.employerContributions] = evidence("Estimated 15% UAE-national pension provision; subsidies, salary caps and fund-specific eligibility are not established.", .estimated,
                ["https://www.gpssa.gov.ae/pages/en/media-center/news/gpssa-insureds-contribution-payment-may-be-extended-15th-day-each-month"])
            provenance[.regionalTax] = evidence("No separate regional income/profit levy is included for the assumed ordinary mainland activity; special sectors require an override.", .estimated)
            provenance[.capitalGains] = evidence("Estimated private-investment treatment: zero personal gain tax. A business asset sale is different and belongs in business profit.")
            provenance[.transactionTax] = evidence("Estimated standard 5% VAT only for explicitly taxable receipts; registration, exemptions and input credits require a separate determination.")
        }
        if country.id == "AE", date.iso < "2023-06-01" {
            business = [TaxBracket(upToMinor: nil, rateBasisPoints: 0)]
            provenance[.businessTax] = evidence("Historical ordinary-activity estimate before federal corporate tax began on 1 June 2023. Special emirate/sector rules are not reconstructed; this is not a blanket exemption.", .estimated,
                ["https://www.moec.gov.ae/en/-/what-are-the-procedures-for-business-incorporation-in-the-ua-1"])
        }
        if country.id == "AE", date.year > 2026 {
            for factor in [FiscalFactor.incomeTax, .businessTax] {
                if let old = provenance[factor] {
                    provenance[factor] = evidence("Future projection of the last bundled reference; future legislation is unknown. " + old.explanation, .estimated, old.sources)
                }
            }
        }
        if country.id == "AE", date.year == 2023, date.iso >= "2023-06-01" {
            for factor in [FiscalFactor.incomeTax, .businessTax] {
                if let old = provenance[factor] {
                    provenance[factor] = RuleEvidence(status: old.status, explanation: old.explanation, sources: old.sources,
                        effectiveFrom: "2023-06-01", effectiveUntil: "2023-12-31")
                }
            }
        }
        if let override = overrides {
            if let rate = override.incomeTaxBasisPoints { income = [TaxBracket(upToMinor: nil, rateBasisPoints: rate)]; provenance[.incomeTax] = evidence("Per-life income-tax override; this replaces the national component only.") }
            if let rate = override.employeeSocialBasisPoints { employee = [PayrollContribution(name: "Per-life employee override", rateBasisPoints: rate)]; provenance[.employeeSocial] = evidence("Per-life employee contribution override without an annual cap.") }
            if let rate = override.employerContributionBasisPoints { employer = [PayrollContribution(name: "Per-life employer override", rateBasisPoints: rate)]; provenance[.employerContributions] = evidence("Per-life employer contribution override without an annual cap.") }
            if let rate = override.businessTaxBasisPoints { business = [TaxBracket(upToMinor: nil, rateBasisPoints: rate)]; provenance[.businessTax] = evidence("Per-life business-tax override; this replaces the national component only.") }
            if let rate = override.capitalGainsBasisPoints { capital = [TaxBracket(upToMinor: nil, rateBasisPoints: rate)]; provenance[.capitalGains] = evidence("Per-life capital-gains override.") }
            if let value = override.annualAllowanceMinor { annualAllowance = value; provenance[.personalAllowance] = evidence("Per-life annual allowance override in accounting minor units.") }
            if let value = override.minimumHourlyWageMinor { minimumWage = value; provenance[.minimumWage] = evidence("Per-life minimum wage override in accounting minor units.") }
            if let value = override.minimumEmploymentAge { minimumAge = value; provenance[.employmentAge] = evidence("Per-life employment age override.") }
            if let value = override.independentAccountAge { accountAge = value; provenance[.accountAge] = evidence("Per-life independent-account age override.") }
            if override.accountingUnitsPerLocalUnit != nil { provenance[.currencyExchange] = evidence("Per-life dated exchange-rate assumption; not a verified market quote.") }
        }
        return FiscalProfile(jurisdiction: jurisdiction, date: date, version: catalog.version, accountingCurrency: accountingCurrency,
            minorUnitsPerUnit: minorUnitsPerUnit, localCurrency: local.code,
            conversion: CurrencyConversionAssumption(date: date, fromCurrency: local.code, toCurrency: accountingCurrency,
                accountingUnitsPerLocalUnit: conversion, status: provenance[.currencyExchange]!.status, explanation: provenance[.currencyExchange]!.explanation),
            provenance: provenance, incomeBrackets: income, annualAllowanceMinor: annualAllowance, employeeContributions: employee,
            employerContributions: employer, businessBrackets: business, capitalGainBrackets: capital, transactionTaxBasisPoints: transactionRate,
            regionalIncomeTaxBasisPoints: regionalIncomeRate, regionalBusinessTaxBasisPoints: regionalBusinessRate,
            minimumHourlyWageMinor: minimumWage, minimumEmploymentAge: minimumAge, independentAccountAge: accountAge,
            taxYearStartMonth: taxYearMonth, taxYearStartDay: taxYearDay, assumptions: assumptions)
    }
}
