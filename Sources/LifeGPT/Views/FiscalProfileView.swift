import SwiftUI
import LifeCore

/// Inspect the exact dated assumptions before applying an override to this life.
struct FiscalProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var jurisdiction: JurisdictionRef?
    let date: GameDate
    let economy: EconomyCard
    private let originalOverrides: FiscalOverrides
    let onSave: (JurisdictionRef, FiscalOverrides) throws -> Void
    @State private var income = ""
    @State private var employee = ""
    @State private var employer = ""
    @State private var business = ""
    @State private var gains = ""
    @State private var exchange = ""
    @State private var error: String?

    init(jurisdiction: JurisdictionRef?, date: GameDate, economy: EconomyCard,
         currentOverrides: FiscalOverrides? = nil,
         onSave: @escaping (JurisdictionRef, FiscalOverrides) throws -> Void) {
        _jurisdiction = State(initialValue: jurisdiction)
        self.date = date; self.economy = economy; self.onSave = onSave
        originalOverrides = currentOverrides ?? FiscalOverrides()
        func percent(_ basis: Int?) -> String { basis.map { String(Double($0) / 100) } ?? "" }
        _income = State(initialValue: percent(currentOverrides?.incomeTaxBasisPoints))
        _employee = State(initialValue: percent(currentOverrides?.employeeSocialBasisPoints))
        _employer = State(initialValue: percent(currentOverrides?.employerContributionBasisPoints))
        _business = State(initialValue: percent(currentOverrides?.businessTaxBasisPoints))
        _gains = State(initialValue: percent(currentOverrides?.capitalGainsBasisPoints))
        _exchange = State(initialValue: currentOverrides?.accountingUnitsPerLocalUnit.map { String($0) } ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tax rules & assumptions").font(.system(size: 26, design: .serif))
                Text("\(date.iso) · Accounting in \(economy.currency). Changes apply from this date; recorded payments retain their original rules.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NationPickerView(selection: $jurisdiction, date: date)
                    if let profile = resolvedProfile {
                        Text("Profile \(profile.version) · Local currency \(profile.localCurrency)").font(.caption).foregroundStyle(.secondary)
                        GroupBox("Current calculation assumptions") {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(profile.assumptions, id: \.self) { Text($0).font(.callout) }
                                Text("Annual personal allowance: \(Money.format(profile.annualAllowanceMinor, economy: economy))")
                                Text("Independent account age: \(profile.independentAccountAge) · Ordinary employment age: \(profile.minimumEmploymentAge)")
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                        }
                        ForEach(FiscalFactor.allCases, id: \.self) { factor in
                            if let evidence = profile.provenance[factor] {
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(evidence.explanation).font(.callout)
                                        Text("Applies: \(evidence.effectiveFrom) through \(evidence.effectiveUntil)").font(.caption).foregroundStyle(.secondary)
                                        ForEach(evidence.sources, id: \.self) { source in
                                            if let url = URL(string: source) { Link(url.host ?? "Source", destination: url).font(.caption) }
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                } label: {
                                    HStack { Text(label(factor)); Spacer(); Text(evidence.status == .notApplicable ? "Not applicable" : evidence.status.rawValue.capitalized).font(.caption).foregroundStyle(evidence.status == .estimated ? Color.orange : Color.secondary) }
                                }
                            }
                        }
                    } else {
                        Text("Choose a complete jurisdiction and valid estimates to preview its dated rules.").font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Overrides for this life").font(.headline)
                    Text("Leave a field blank to use its preset. Enter percentages from 0 to 100. Edited rates are labeled estimates. National tax overrides leave regional components intact; replacing contribution rates removes their preset annual cap.")
                        .font(.caption).foregroundStyle(.secondary)
                    rateField("National income tax", text: $income)
                    rateField("Employee social contributions", text: $employee)
                    rateField("Employer contributions", text: $employer)
                    rateField("National business tax", text: $business)
                    rateField("Personal capital gains", text: $gains)
                    HStack {
                        Text("\(economy.currency) units per local currency unit").font(.callout)
                        Spacer()
                        TextField("Preset conversion", text: $exchange).multilineTextAlignment(.trailing).frame(width: 145)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                }.padding(24)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply from \(date.iso)") { save() }.buttonStyle(.borderedProminent).disabled(jurisdiction == nil)
            }.padding(20)
        }.textFieldStyle(.roundedBorder).frame(width: 680, height: 740)
    }
    private var resolvedProfile: FiscalProfile? {
        guard let jurisdiction, let override = try? edits() else { return nil }
        return try? FiscalRuleResolver.resolve(jurisdiction: jurisdiction, on: date, accountingCurrency: economy.currency,
                                               minorUnitsPerUnit: economy.minorUnitsPerUnit, overrides: override)
    }
    private func rateField(_ label: String, text: Binding<String>) -> some View {
        HStack { Text(label).font(.callout); Spacer(); TextField("Preset", text: text).multilineTextAlignment(.trailing).frame(width: 110); Text("%") }
    }
    private func edits() throws -> FiscalOverrides {
        func rate(_ raw: String) throws -> Int? {
            let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return nil }
            guard let value = Double(raw), value.isFinite, (0...100).contains(value) else { throw ValidationError.invalid("Enter a percentage from 0 to 100, or leave it blank.") }
            return Int((value * 100).rounded())
        }
        var result = originalOverrides
        result.incomeTaxBasisPoints = try rate(income); result.employeeSocialBasisPoints = try rate(employee)
        result.employerContributionBasisPoints = try rate(employer); result.businessTaxBasisPoints = try rate(business)
        result.capitalGainsBasisPoints = try rate(gains)
        let rawFX = exchange.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawFX.isEmpty { result.accountingUnitsPerLocalUnit = nil }
        else {
            guard let value = Double(rawFX), value.isFinite, value > 0 else { throw ValidationError.invalid("Enter a positive exchange-rate estimate, or leave it blank.") }
            result.accountingUnitsPerLocalUnit = value
        }
        try result.validate(); return result
    }
    private func save() {
        do {
            guard let jurisdiction else { throw ValidationError.invalid("Choose a preset nation.") }
            let value = try edits()
            _ = try FiscalRuleResolver.resolve(jurisdiction: jurisdiction, on: date, accountingCurrency: economy.currency,
                                               minorUnitsPerUnit: economy.minorUnitsPerUnit, overrides: value)
            try onSave(jurisdiction, value); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func label(_ factor: FiscalFactor) -> String {
        switch factor {
        case .incomeTax: "Income tax"
        case .personalAllowance: "Personal allowance"
        case .employeeSocial: "Employee contributions"
        case .employerContributions: "Employer contributions"
        case .businessTax: "Business profit tax"
        case .capitalGains: "Personal capital gains"
        case .transactionTax: "Taxable transactions"
        case .taxCalendar: "Tax calendar"
        case .currencyExchange: "Currency conversion"
        case .wages: "Wage estimates"
        case .livingCosts: "Living costs"
        case .minimumWage: "Minimum wage"
        case .employmentAge: "Employment eligibility"
        case .accountAge: "Account eligibility"
        case .regionalTax: "Regional taxes"
        }
    }
}
