import SwiftUI
import LifeCore

struct BusinessManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let snapshot: LifeSnapshot
    @State private var tab = "records"
    @State private var companyID = ""
    @State private var companyName = ""
    @State private var accountName = ""
    @State private var accountID = ""
    @State private var companyJurisdiction: JurisdictionRef?
    @State private var workJurisdiction: JurisdictionRef?
    @State private var employeeTaxResidence: JurisdictionRef?
    @State private var ownerTaxResidence: JurisdictionRef?
    @State private var structure = BusinessRecord.LegalStructure.incorporated
    @State private var conversion = false
    @State private var obligationID = ""
    @State private var obligationKind = RecurringObligation.Kind.revenue
    @State private var obligationName = ""
    @State private var monthly = ""
    @State private var headcount = 1
    @State private var paymentDestination = ""
    @State private var closureDestination = ""
    @State private var saleDestination = ""
    @State private var birthDate = ""
    @State private var hours = ""
    @State private var buyer = ""
    @State private var retainedLiabilities = Set<String>()
    @State private var salePrice = ""
    @State private var selectedAccount = ""
    @State private var lifecycleAction = AccountLifecycleChange.Action.close
    @State private var replacement = ""
    @State private var error: String?
    @State private var showTax = false

    init(snapshot: LifeSnapshot) {
        self.snapshot = snapshot
        let initialCompany = snapshot.business.businesses.first { $0.status == .active }
        let initialJurisdiction = initialCompany?.jurisdiction(on: snapshot.character.currentDate) ?? snapshot.currentResidence
        _companyID = State(initialValue: initialCompany?.id ?? "")
        _companyJurisdiction = State(initialValue: initialJurisdiction)
        _workJurisdiction = State(initialValue: initialJurisdiction)
        _employeeTaxResidence = State(initialValue: snapshot.currentResidence)
        _ownerTaxResidence = State(initialValue: snapshot.currentResidence)
        _paymentDestination = State(initialValue: snapshot.business.defaultPersonalAccountId)
        _closureDestination = State(initialValue: snapshot.business.defaultPersonalAccountId)
        _saleDestination = State(initialValue: snapshot.business.defaultPersonalAccountId)
        _replacement = State(initialValue: snapshot.business.defaultPersonalAccountId)
        _selectedAccount = State(initialValue: snapshot.accessibleAccounts.first?.id ?? "")
    }
    private var date: GameDate { snapshot.character.currentDate }
    private var companies: [BusinessRecord] { snapshot.business.businesses.filter { $0.status == .active } }
    private var company: BusinessRecord? { companies.first { $0.id == companyID } }
    private var taxProfileJurisdiction: JurisdictionRef? {
        switch tab {
        case "payments": workJurisdiction
        case "sales": ownerTaxResidence
        default: companyJurisdiction ?? snapshot.currentResidence
        }
    }
    private var taxProfileTitle: String {
        switch tab {
        case "payments": "Payment work tax rules & assumptions…"
        case "sales": "Sale owner tax rules & assumptions…"
        default: "Company tax rules & assumptions…"
        }
    }
    private var stale: Bool { model.snapshot?.character.id != snapshot.character.id || model.snapshot?.revision != snapshot.revision }
    private func money(_ amount: Int64) -> String { Money.format(amount, economy: snapshot.economy) }
    private func amount(_ text: String) throws -> Int64 {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              text.count < 40, let value = Decimal(string: text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) else {
            throw ValidationError.invalid("Enter a positive amount such as 50,000.00 without a currency symbol.")
        }
        var minor = value * Decimal(snapshot.economy.minorUnitsPerUnit), rounded = Decimal()
        NSDecimalRound(&rounded, &minor, 0, .plain)
        guard !minor.isNaN, minor > 0, minor <= 1_000_000_000_000, rounded == minor else {
            throw ValidationError.invalid("Enter a supported positive amount in whole currency minor units.")
        }
        return NSDecimalNumber(decimal: minor).int64Value
    }
    private func unique(_ prefix: String) -> String { prefix + "-" + UUID().uuidString.lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Businesses & payroll").font(.system(size: 28, design: .serif))
            Text("\(date.iso) · \(snapshot.economy.currency) · Changes begin today. Monthly amounts accrue in arrears; earlier payments stay unchanged.")
                .font(.callout).foregroundStyle(.secondary)
            TabView(selection: $tab) {
                records.tabItem { Text("Records") }.tag("records")
                companyForm.tabItem { Text("Company") }.tag("company")
                obligationForm.tabItem { Text("Payments") }.tag("payments")
                accountsForm.tabItem { Text("Account access") }.tag("accounts")
                salesForm.tabItem { Text("Sale review") }.tag("sales")
            }
            .disabled(model.busy || stale || snapshot.ended)
            if stale { Text("This life changed. Close and reopen these records before editing.").foregroundStyle(.orange) }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(taxProfileTitle) { showTax = true }.disabled(stale || snapshot.ended)
            }
        }.padding(24).frame(width: 790, height: 790)
        .sheet(isPresented: $showTax) {
            FiscalProfileView(jurisdiction: taxProfileJurisdiction, date: date, economy: snapshot.economy,
                currentOverrides: snapshot.business.fiscalOverrides.last { $0.jurisdiction.countryID == taxProfileJurisdiction?.countryID && $0.jurisdiction.subdivisionID == taxProfileJurisdiction?.subdivisionID }?.values) { ref, values in
                try model.updateFiscalProfile(jurisdiction: ref, values: values, lifeID: snapshot.character.id, revision: snapshot.revision)
            }
        }
        .onChange(of: companyID) { _, _ in
            companyJurisdiction = company?.jurisdiction(on: date) ?? snapshot.currentResidence
            companyName = ""; obligationID = ""; retainedLiabilities = []
            resetPaymentDraft()
        }
        .onChange(of: selectedAccount) { _, _ in accountName = "" }
        .onChange(of: obligationID) { _, id in
            guard let record = snapshot.currentObligations.first(where: { $0.id == id && $0.businessId == companyID }) else {
                resetPaymentDraft(); return
            }
            obligationKind = record.kind; obligationName = record.name
            monthly = NSDecimalNumber(decimal: Decimal(record.monthlyMinor) / Decimal(snapshot.economy.minorUnitsPerUnit)).stringValue
            headcount = record.headcount; workJurisdiction = record.jurisdiction ?? company?.jurisdiction(on: date)
            employeeTaxResidence = record.taxResidence ?? record.jurisdiction
            paymentDestination = record.toAccountId ?? snapshot.business.defaultPersonalAccountId
            birthDate = record.employeeBirthDate?.iso ?? ""; hours = record.monthlyHours.map(String.init) ?? ""
        }
    }
    private var records: some View {
        Form {
            Section("Cash and obligations") {
                LabeledContent("Company cash", value: money(snapshot.businessCash))
                LabeledContent("Personal account", value: money(snapshot.personalBalance))
                LabeledContent("Reserved taxes — unavailable to spend", value: money(snapshot.reservedTaxes))
                LabeledContent("Unpaid obligations", value: money(snapshot.unpaidObligations))
                ForEach(RecurringObligation.Kind.allCases, id: \.self) { kind in
                    LabeledContent("\(label(kind)) / month", value: money(snapshot.monthlyTotal(kind)))
                }
                Text("Due taxes, employees, operating costs, then owner pay. Oldest bills first; equal-priority bills share available funds. Personal savings never cover company shortfalls automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Companies") {
                if snapshot.business.businesses.isEmpty { Text("Create a company to begin gross revenue, payroll, and tax accounting.") }
                ForEach(snapshot.business.businesses) { company in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(company.name).bold()
                        Text("\(company.status.rawValue) · \(company.legalStructure.rawValue) · \(CountryCatalog.shared.displayName(company.jurisdiction(on: date)))")
                        Text("Account: \(company.accountId) · Started \(company.openedOn.iso)").font(.caption)
                    }
                }
            }
            Section("Recent monthly statements") {
                ForEach(Array(snapshot.business.assessments.suffix(12).reversed())) { statement in
                    DisclosureGroup("\(statement.businessId) · \(statement.periodStart.iso)–\(statement.periodEnd.iso)") {
                        LabeledContent("Gross revenue", value: money(statement.revenueMinor))
                        LabeledContent("Gross payroll / owner pay", value: money(statement.grossPayrollMinor))
                        LabeledContent("Employer charges", value: money(statement.employerChargesMinor))
                        LabeledContent("Operating expenses", value: money(statement.expensesMinor))
                        LabeledContent("Taxable profit", value: money(statement.taxableProfitMinor))
                        LabeledContent("Business tax", value: money(statement.businessTaxMinor))
                        ForEach(Array(statement.profiles.enumerated()), id: \.offset) { _, profile in Text(profile.summary).font(.caption).textSelection(.enabled) }
                    }
                }
            }
            Section("Unpaid bills") {
                ForEach(snapshot.business.payables.filter { $0.remainingMinor > 0 && snapshot.ownedBusinessIDs.contains($0.businessId) }) { payable in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("\(payable.name) · due \(payable.dueOn.iso)", value: money(payable.remainingMinor))
                        if let issue = payable.routingIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        }.formStyle(.grouped)
    }
    private var companyForm: some View {
        Form {
            Section("Create a company") {
                TextField("Company name", text: $companyName)
                Picker("Operating account", selection: $accountID) {
                    Text("Open a new company account").tag("")
                    ForEach(snapshot.accessibleAccounts.filter { $0.kind == .business && $0.businessId == nil }) { Text($0.name).tag($0.id) }
                }
                Picker("Legal structure", selection: $structure) {
                    ForEach(BusinessRecord.LegalStructure.allCases, id: \.self) { Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
                }
                NationPickerView(selection: $companyJurisdiction, date: date)
                Toggle("Convert legacy net income on this account from today", isOn: $conversion)
                Text("Conversion ends existing net-income sources on that account. Add explicit gross revenue and payroll under Payments. No earlier earnings or taxes are backfilled.").font(.caption).foregroundStyle(.secondary)
                Button("Create company") { perform {
                    guard let companyJurisdiction else { throw ValidationError.invalid("Select a preset jurisdiction.") }
                    try update(business: [BusinessChange(action: .create, id: unique("company"), name: companyName,
                        accountId: accountID.isEmpty ? unique("business") : accountID, jurisdiction: companyJurisdiction,
                        legalStructure: structure, effectiveFrom: date.iso)], convert: conversion)
                } }.buttonStyle(.borderedProminent)
            }
            Section("Existing company") {
                companyPicker
                Text("Rename or relocate the selected company using the name and jurisdiction above. Its earlier jurisdiction records stay dated.").font(.caption)
                Button("Apply company update") { perform {
                    guard let company else { throw ValidationError.invalid("Choose a company.") }
                    try update(business: [BusinessChange(action: .update, id: company.id, name: companyName.isEmpty ? nil : companyName,
                        jurisdiction: companyJurisdiction, effectiveFrom: date.iso)])
                } }
                Button("End operations from today") { perform {
                    guard let company else { throw ValidationError.invalid("Choose a company.") }
                    try update(business: [BusinessChange(action: .end, id: company.id, effectiveFrom: date.iso)])
                } }
            }
        }.formStyle(.grouped)
    }
    private var obligationForm: some View {
        Form {
            Section("Dated recurring payment") {
                companyPicker
                Picker("Record", selection: $obligationID) {
                    Text("New recurring record").tag("")
                    ForEach(snapshot.currentObligations.filter { $0.businessId == companyID }) { Text($0.name).tag($0.id) }
                }
                Picker("Kind", selection: $obligationKind) {
                    ForEach(RecurringObligation.Kind.allCases, id: \.self) { Text(label($0)).tag($0) }
                }
                TextField("Name", text: $obligationName)
                TextField("Gross amount / month (\(snapshot.economy.currency))", text: $monthly, prompt: Text("50000.00"))
                if obligationKind == .payroll {
                    Stepper("Employees with identical terms: \(headcount)", value: $headcount, in: 1...100000)
                    Text("The monthly amount is per employee. Use separate records for different salaries or tax histories.").font(.caption)
                }
                if obligationKind == .payroll || obligationKind == .ownerSalary {
                    Text("Work jurisdiction").bold()
                    NationPickerView(selection: $workJurisdiction, date: date)
                    Text("Tax residence").bold()
                    NationPickerView(selection: $employeeTaxResidence, date: date)
                    TextField("Birth date, if applicable (YYYY-MM-DD)", text: $birthDate)
                    TextField("Contract hours per month", text: $hours)
                    Text("Age and minimum-pay checks need the corresponding contract details. Missing details are not a verified employment eligibility check.").font(.caption).foregroundStyle(.secondary)
                }
                if obligationKind == .ownerSalary || obligationKind == .transfer {
                    Picker("Destination", selection: $paymentDestination) {
                        ForEach(snapshot.accessibleAccounts.filter { obligationKind != .ownerSalary || ($0.kind == .personal && $0.businessId == nil) }) { Text($0.name).tag($0.id) }
                    }
                }
                Text("Gross owner pay debits the company; only net pay reaches personal funds. Employee deductions go into restricted tax reserves. Missing cash creates a payable.").font(.caption).foregroundStyle(.secondary)
                Button(obligationID.isEmpty ? "Start recurring record" : "Apply new terms") { perform {
                    guard let company else { throw ValidationError.invalid("Choose a company first.") }
                    let payroll = obligationKind == .payroll || obligationKind == .ownerSalary
                    guard !payroll || (workJurisdiction != nil && employeeTaxResidence != nil) else { throw ValidationError.invalid("Select the work jurisdiction and tax residence.") }
                    if !hours.isEmpty && Int(hours) == nil { throw ValidationError.invalid("Contract hours must be a whole number.") }
                    let change = ObligationChange(action: obligationID.isEmpty ? .start : .change,
                        id: obligationID.isEmpty ? unique("payment") : obligationID, businessId: company.id,
                        kind: obligationKind, name: obligationName, monthlyMinor: try amount(monthly),
                        headcount: obligationKind == .payroll ? headcount : 1, fromAccountId: company.accountId,
                        toAccountId: [.ownerSalary, .transfer].contains(obligationKind) ? paymentDestination : nil,
                        jurisdiction: payroll ? workJurisdiction : company.jurisdiction(on: date), taxResidence: payroll ? employeeTaxResidence : nil,
                        employeeBirthDate: birthDate.isEmpty ? nil : birthDate, monthlyHours: Int(hours), effectiveFrom: date.iso)
                    try update(obligations: [change])
                } }.buttonStyle(.borderedProminent)
                if !obligationID.isEmpty {
                    Button("End this record today") { perform { try update(obligations: [ObligationChange(action: .end, id: obligationID, effectiveFrom: date.iso)]) } }
                }
            }
        }.formStyle(.grouped)
    }
    private var accountsForm: some View {
        Form {
            Section("Account lifecycle") {
                Picker("Account", selection: $selectedAccount) { ForEach(snapshot.accessibleAccounts) { Text($0.name).tag($0.id) } }
                Picker("Change", selection: $lifecycleAction) {
                    Text("Close").tag(AccountLifecycleChange.Action.close)
                    Text("Rename").tag(AccountLifecycleChange.Action.rename)
                    Text("Make default personal").tag(AccountLifecycleChange.Action.setDefault)
                }
                if lifecycleAction == .rename { TextField("New name", text: $accountName) }
                if lifecycleAction == .close {
                    Picker("Move remaining balance to", selection: $closureDestination) {
                        ForEach(snapshot.accessibleAccounts.filter { $0.id != selectedAccount }) { Text($0.name).tag($0.id) }
                    }
                    Picker("Replacement default personal account", selection: $replacement) {
                        ForEach(snapshot.accessibleAccounts.filter { $0.id != selectedAccount && $0.kind == .personal && $0.businessId == nil }) { Text($0.name).tag($0.id) }
                    }
                    Text("First resolve linked assets, loans, income, accrued payroll and unpaid bills. History remains readable after closure.").font(.caption)
                }
                Button("Apply account change") { perform {
                    try update(accounts: [AccountLifecycleChange(action: lifecycleAction, accountId: selectedAccount,
                        name: lifecycleAction == .rename ? accountName : nil, balanceDestinationAccountId: closureDestination,
                        replacementAccountId: replacement, effectiveFrom: date.iso)])
                } }.buttonStyle(.borderedProminent)
            }
        }.formStyle(.grouped)
    }
    private var salesForm: some View {
        Form {
            Section("Prepare a complete sale") {
                companyPicker
                TextField("Buyer", text: $buyer)
                TextField("Sale price (\(snapshot.economy.currency))", text: $salePrice)
                Picker("Personal proceeds account", selection: $saleDestination) {
                    ForEach(snapshot.accessibleAccounts.filter { $0.businessId == nil && $0.kind == .personal }) { Text($0.name).tag($0.id) }
                }
                Text("Owner's tax residence").bold()
                NationPickerView(selection: $ownerTaxResidence, date: date)
                ForEach(snapshot.positions.filter { $0.isDebt && $0.accountId == company?.accountId }) { position in
                    Toggle("Retain personal liability: \(position.name) (\(money(position.principalMinor)))", isOn: Binding(
                        get: { retainedLiabilities.contains(position.id) },
                        set: { if $0 { retainedLiabilities.insert(position.id) } else { retainedLiabilities.remove(position.id) } }))
                }
                Text("This review sells 100%. All company accounts, company-linked assets and obligations transfer; no management or employment rights are retained. Personal liabilities remain yours. Partial ownership and retained rights need separate support.").font(.caption).foregroundStyle(.secondary)
                Button("Prepare sale review") { perform {
                    guard let company, let ownerTaxResidence else { throw ValidationError.invalid("Select a company and the owner's tax residence.") }
                    try update(sales: [SaleProposal(id: unique("sale"), businessId: company.id, buyer: buyer,
                        priceMinor: try amount(salePrice), destinationAccountId: saleDestination, effectiveFrom: date.iso, ownerJurisdiction: ownerTaxResidence, retainedLiabilityIds: Array(retainedLiabilities).sorted())])
                } }
            }
            ForEach(snapshot.business.saleDrafts.filter { $0.confirmedOn == nil }) { draft in
                Section("Review: \(draft.proposal.businessId)") {
                    LabeledContent("Buyer / date", value: "\(draft.proposal.buyer) · \(draft.proposal.effectiveFrom)")
                    LabeledContent("Ownership sold", value: "100%")
                    LabeledContent("Price", value: money(draft.proposal.priceMinor))
                    LabeledContent("Estimated gains tax", value: money(draft.estimatedTaxMinor))
                    LabeledContent("Net proceeds", value: money(max(0, draft.proposal.priceMinor - draft.estimatedTaxMinor)))
                    LabeledContent("Transferred accounts", value: draft.transferredAccountIds.joined(separator: ", "))
                    ForEach(snapshot.positions.filter { draft.transferredAccountIds.contains($0.accountId ?? "personal") }) { position in
                        LabeledContent("Transfers: \(position.name)", value: money(position.principalMinor))
                    }
                    LabeledContent("Unpaid company obligations transfer", value: money(snapshot.business.payables.filter { $0.businessId == draft.proposal.businessId }.reduce(0) { $0 + $1.remainingMinor }))
                    LabeledContent("Retained personal debt IDs", value: (draft.proposal.retainedLiabilityIds ?? []).joined(separator: ", "))
                    Text(draft.fiscalProfile.summary).font(.caption).textSelection(.enabled)
                    ForEach(draft.assumptions, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    if let preview = try? BusinessEngine.confirmSale(id: draft.id, expectedRevision: snapshot.revision,
                        currentRevision: snapshot.revision, state: snapshot.business, accounts: snapshot.accounts, date: date, economy: snapshot.economy) {
                        DisclosureGroup("Settlement and accounts that transfer") {
                            ForEach(preview.accounts.filter { $0.businessId == draft.proposal.businessId }) { account in
                                LabeledContent(account.name, value: money(account.balanceMinor))
                            }
                            LabeledContent("Company obligations after closeout", value: money(preview.state.payables.filter { $0.businessId == draft.proposal.businessId }.reduce(0) { $0 + $1.remainingMinor }))
                        }
                    }
                    Text("Activity is settled through the sale date before transfer. Company cash is not added to the price. Company access and owner pay end; personal debts remain. Confirmation is bound to this exact save revision.").font(.caption)
                    Button("Confirm this complete sale") { perform {
                        try model.confirmSale(draft.id, lifeID: snapshot.character.id, revision: snapshot.revision)
                    } }.buttonStyle(.borderedProminent).disabled(draft.reviewedRevision != snapshot.revision)
                    if draft.reviewedRevision != snapshot.revision { Text("Stale review: prepare the sale again using current records.").foregroundStyle(.orange) }
                }
            }
        }.formStyle(.grouped)
    }
    private var companyPicker: some View {
        Picker("Company", selection: $companyID) {
            if companies.isEmpty { Text("Create a company first").tag("") }
            ForEach(companies) { Text($0.name).tag($0.id) }
        }
    }
    private func resetPaymentDraft() {
        obligationKind = .revenue; obligationName = ""; monthly = ""; headcount = 1
        workJurisdiction = company?.jurisdiction(on: date) ?? snapshot.currentResidence
        employeeTaxResidence = snapshot.currentResidence
        paymentDestination = snapshot.business.defaultPersonalAccountId
        birthDate = ""; hours = ""
    }
    private func label(_ kind: RecurringObligation.Kind) -> String {
        switch kind { case .revenue: "Gross revenue"; case .payroll: "Employee payroll"; case .ownerSalary: "Gross owner salary"; case .expense: "Operating expenses"; case .transfer: "Scheduled transfers" }
    }
    private func update(business: [BusinessChange] = [], obligations: [ObligationChange] = [], accounts: [AccountLifecycleChange] = [], sales: [SaleProposal] = [], convert: Bool = false) throws {
        try model.updateBusinesses(businessChanges: business, obligations: obligations, accounts: accounts, sales: sales,
            convertLegacy: convert, expectedLifeID: snapshot.character.id, expectedRevision: snapshot.revision)
    }
    private func perform(_ action: () throws -> Void) {
        error = nil
        do { guard !stale, !model.busy else { throw ValidationError.invalid("Reopen current records before editing.") }; try action(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
