import SwiftUI
import LifeCore

struct FinanceManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let snapshot: LifeSnapshot

    @State private var tab = "income"
    @State private var incomeAction = IncomeStreamChange.Action.start
    @State private var selectedIncomeName = ""
    @State private var incomeName = ""
    @State private var incomeKind = IncomeStream.Kind.business
    @State private var incomeTier = ""
    @State private var monthlyAmount = ""
    @State private var receivingAccountID = ""
    @State private var incomePathID = ""
    @State private var incomeReason = ""

    @State private var openingID: String
    @State private var accountName = ""
    @State private var accountKind = BankAccount.Kind.business

    @State private var transferFromID = ""
    @State private var transferToID = ""
    @State private var transferAmount = ""
    @State private var transferReason = ""
    @State private var error: String?

    init(snapshot: LifeSnapshot) {
        self.snapshot = snapshot
        let source = snapshot.accounts.first(where: { $0.balanceMinor > 0 }) ?? snapshot.accounts.first
        _openingID = State(initialValue: "account-" + UUID().uuidString.lowercased())
        _receivingAccountID = State(initialValue: snapshot.accounts.first(where: { $0.kind == .business })?.id
            ?? snapshot.accounts.first?.id ?? "")
        _transferFromID = State(initialValue: source?.id ?? "")
        _transferToID = State(initialValue: snapshot.accounts.first(where: { $0.id != source?.id })?.id ?? "")
        _selectedIncomeName = State(initialValue: snapshot.streams.first(where: { $0.endedOn == nil })?.name ?? "")
        _incomeTier = State(initialValue: snapshot.economy.wageBands.first?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Manage finances").font(.system(size: 28, design: .serif))
                Text("Review a change, then apply it to this life.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Effective date: \(snapshot.character.currentDate.iso) · \(snapshot.economy.currency)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            TabView(selection: $tab) {
                incomeForm.tabItem { Label("Income", systemImage: "calendar.badge.clock") }.tag("income")
                accountsForm.tabItem { Label("Accounts", systemImage: "building.columns") }.tag("accounts")
                transferForm.tabItem { Label("Transfer", systemImage: "arrow.left.arrow.right") }.tag("transfer")
            }
            .disabled(model.busy || isStale || snapshot.ended)

            if isStale {
                errorLabel("This life changed while this sheet was open. Close and reopen Manage finances to use its current records.")
            } else if snapshot.ended {
                errorLabel("This life has ended. Its financial history remains available to read.")
            } else if let error {
                errorLabel(error)
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("Applies the selected tab.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(applyTitle) { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy || isStale || snapshot.ended || !hasRequiredFields)
            }
        }
        .padding(26)
        .frame(width: 690, height: 750)
        .onChange(of: incomeAction) { _, action in
            error = nil
            incomeReason = ""
            if action == .start {
                incomeName = ""; monthlyAmount = ""; incomeKind = .business; incomePathID = ""
                receivingAccountID = snapshot.accounts.first(where: { $0.kind == .business })?.id
                    ?? snapshot.accounts.first?.id ?? ""
            } else {
                if selectedIncome == nil { selectedIncomeName = activeStreams.first?.name ?? "" }
                loadSelectedIncome()
            }
        }
        .onChange(of: selectedIncomeName) { _, _ in
            incomeReason = ""
            loadSelectedIncome()
        }
        .onChange(of: incomeKind) { _, kind in
            if kind != .business { incomePathID = "" }
        }
        .onChange(of: transferFromID) { _, source in
            if transferToID == source {
                transferToID = snapshot.accounts.first(where: { $0.id != source })?.id ?? ""
            }
        }
        .onChange(of: tab) { _, _ in error = nil }
    }

    private var incomeForm: some View {
        Form {
            Section {
                Picker("Change", selection: $incomeAction) {
                    Text("Start").tag(IncomeStreamChange.Action.start)
                    Text("Change").tag(IncomeStreamChange.Action.change)
                    Text("End").tag(IncomeStreamChange.Action.end)
                }.pickerStyle(.segmented)
                if incomeAction == .start {
                    TextField("Income source", text: $incomeName, prompt: Text("Website profit"))
                    Picker("Type", selection: $incomeKind) {
                        ForEach(incomeKinds, id: \.rawValue) { kind in Text(kindLabel(kind)).tag(kind) }
                    }
                } else if activeStreams.isEmpty {
                    Text("There is no active income to change or end. Choose Start to record a source.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Existing source", selection: $selectedIncomeName) {
                        ForEach(activeStreams, id: \.name) { stream in Text(stream.name).tag(stream.name) }
                    }
                    if let stream = selectedIncome {
                        if incomeAction == .change {
                            Picker("Type", selection: $incomeKind) {
                                ForEach(incomeKinds, id: \.rawValue) { kind in Text(kindLabel(kind)).tag(kind) }
                            }
                        } else { LabeledContent("Type", value: kindLabel(stream.kind)) }
                        LabeledContent("Current monthly amount", value: money(stream.monthlyMinor))
                        LabeledContent("Current account", value: accountLabel(stream.accountId))
                    }
                }
            }

            if incomeAction == .start || selectedIncome != nil {
                if incomeAction != .end {
                    Section {
                        TextField("\(snapshot.economy.currency) per month", text: $monthlyAmount, prompt: Text("50000.00"))
                        Text("Enter NET spendable income after business costs, rather than sales revenue. Use a decimal point, such as 50,000.00. This recurring rate is paid as time passes.")
                            .font(.caption).foregroundStyle(.secondary)
                        accountPicker("Paid into", selection: $receivingAccountID)
                        if incomeKind == .wage {
                            Picker("Wage tier", selection: $incomeTier) {
                                if incomeTier.isEmpty { Text("Choose a tier").tag("") }
                                ForEach(snapshot.economy.wageBands, id: \.name) { band in
                                    Text(band.name.capitalized).tag(band.name)
                                }
                            }
                            if let band = snapshot.economy.wageBands.first(where: { $0.name == incomeTier }) {
                                Text("This tier: \(money(band.minMonthlyMinor)) to \(money(band.maxMonthlyMinor)) per month. The selected play style determines the applicable rules.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if incomeKind == .business {
                            Picker("Related business path", selection: $incomePathID) {
                                if incomeAction == .start || selectedIncome?.pathId == nil {
                                    Text("No linked path").tag("")
                                }
                                if let existing = selectedIncome?.pathId,
                                   incomeAction != .start,
                                   !snapshot.paths.contains(where: { $0.id == existing }) {
                                    Text("Existing link: \(existing)").tag(existing)
                                }
                                ForEach(snapshot.paths) { path in Text(path.title).tag(path.id) }
                            }
                            Text("Choose a recorded business path when it represents this same income source. An existing link is preserved unless you choose another path.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("Recurring income") }
                }

                Section {
                    TextField("Reason for this change", text: $incomeReason, axis: .vertical).lineLimit(2...4)
                    if incomeAction == .end {
                        Text("Payments from this source stop from \(snapshot.character.currentDate.iso). Its previous payments stay in the ledger.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Effective from \(snapshot.character.currentDate.iso). Earlier months are not credited again. Changes are validated before they are saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Record the change") }
            }

            if !endedStreams.isEmpty {
                Section {
                    DisclosureGroup("Ended income history (\(endedStreams.count))") {
                        ForEach(Array(endedStreams.enumerated()), id: \.offset) { _, stream in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stream.name).font(.callout.weight(.medium))
                                Text("\(money(stream.monthlyMinor)) / month · Ended \(stream.endedOn?.iso ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                    }
                    Text("Ended sources stay in history. Choose Start to resume a source from today's date.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }

    private var accountsForm: some View {
        Form {
            Section("Recorded accounts") {
                ForEach(snapshot.accounts) { account in
                    LabeledContent {
                        Text(money(account.balanceMinor)).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                            Text(account.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                TextField("Account name", text: $accountName, prompt: Text("Website business account"))
                Picker("Type", selection: $accountKind) {
                    ForEach(BankAccount.Kind.allCases, id: \.rawValue) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                Text("New accounts open with \(money(0)). After opening one, use Transfer to move existing funds or Income to direct recurring payments into it.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Open an account") }
        }.formStyle(.grouped)
    }

    private var transferForm: some View {
        Form {
            Section {
                if snapshot.accounts.count < 2 {
                    Text("Open another account before transferring money between accounts.")
                        .foregroundStyle(.secondary)
                } else {
                    accountPicker("From", selection: $transferFromID)
                    if let source = snapshot.accounts.first(where: { $0.id == transferFromID }) {
                        LabeledContent("Available in source", value: money(source.balanceMinor))
                    }
                    Picker("To", selection: $transferToID) {
                        ForEach(snapshot.accounts.filter { $0.id != transferFromID }) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    TextField("Amount (\(snapshot.economy.currency))", text: $transferAmount, prompt: Text("10000.00"))
                    TextField("Reason for the transfer", text: $transferReason, axis: .vertical).lineLimit(2...4)
                    Text("Move existing funds between your accounts. Total cash stays the same, and this transfer is not new income. Use a positive amount that the source account can cover.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let amount = try? parseAmount(transferAmount) {
                        Text("\(money(amount)) from \(accountLabel(transferFromID)) to \(accountLabel(transferToID)).")
                            .font(.callout.weight(.medium))
                    }
                }
            } header: { Text("Transfer funds") }
        }.formStyle(.grouped)
    }

    private var activeStreams: [IncomeStream] { snapshot.streams.filter { $0.endedOn == nil } }
    private var endedStreams: [IncomeStream] { snapshot.streams.filter { $0.endedOn != nil } }
    private var selectedIncome: IncomeStream? { activeStreams.first { $0.name == selectedIncomeName } }
    private var incomeKinds: [IncomeStream.Kind] { [.wage, .selfEmployment, .business, .allowance, .rental] }
    private var isStale: Bool {
        model.snapshot?.character.id != snapshot.character.id || model.snapshot?.revision != snapshot.revision
    }
    private var applyTitle: String {
        switch tab {
        case "accounts": return "Open account"
        case "transfer": return "Transfer funds"
        default: return incomeAction == .end ? "End income" : "Apply income change"
        }
    }
    private var hasRequiredFields: Bool {
        switch tab {
        case "accounts": return !trimmed(accountName).isEmpty
        case "transfer":
            return snapshot.accounts.count >= 2 && !trimmed(transferAmount).isEmpty && !trimmed(transferReason).isEmpty
        default:
            let hasSource = incomeAction == .start ? !trimmed(incomeName).isEmpty : selectedIncome != nil
            return hasSource && !trimmed(incomeReason).isEmpty
                && (incomeAction == .end || (!trimmed(monthlyAmount).isEmpty && !receivingAccountID.isEmpty))
        }
    }

    private func accountPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            if snapshot.accounts.isEmpty { Text("Open an account first").tag("") }
            ForEach(snapshot.accounts) { account in Text(account.name).tag(account.id) }
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.callout).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func loadSelectedIncome() {
        guard incomeAction != .start, let stream = selectedIncome else { return }
        incomeKind = stream.kind
        incomeTier = stream.tier ?? snapshot.economy.wageBands.first?.name ?? ""
        monthlyAmount = NSDecimalNumber(decimal: Decimal(stream.monthlyMinor)
            / Decimal(max(1, snapshot.economy.minorUnitsPerUnit))).stringValue
        receivingAccountID = stream.accountId
        incomePathID = stream.pathId ?? ""
    }

    private func apply() {
        error = nil
        do {
            guard !model.busy, !isStale, !snapshot.ended else {
                throw ValidationError.invalid("Close and reopen Manage finances before applying this change.")
            }
            switch tab {
            case "accounts":
                let name = trimmed(accountName)
                guard !name.isEmpty else { throw ValidationError.invalid("Enter a name for the new account.") }
                guard !snapshot.accounts.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw ValidationError.invalid("An account already has that name. Choose a distinct name.")
                }
                try model.updateFinances(accountOpenings: [AccountOpening(id: openingID, name: name, kind: accountKind)],
                    streamChanges: [], transfers: [], expectedLifeID: snapshot.character.id, expectedRevision: snapshot.revision)
            case "transfer":
                let amount = try parseAmount(transferAmount)
                guard let source = snapshot.accounts.first(where: { $0.id == transferFromID }),
                      snapshot.accounts.contains(where: { $0.id == transferToID }), transferFromID != transferToID else {
                    throw ValidationError.invalid("Choose two different recorded accounts.")
                }
                guard amount <= source.balanceMinor else {
                    throw ValidationError.invalid("\(source.name) has \(money(source.balanceMinor)) available. Enter an amount it can cover.")
                }
                let reason = try requiredReason(transferReason)
                try model.updateFinances(accountOpenings: [], streamChanges: [],
                    transfers: [AccountTransfer(fromAccount: transferFromID, toAccount: transferToID, amountMinor: amount, reason: reason)],
                    expectedLifeID: snapshot.character.id, expectedRevision: snapshot.revision)
            default:
                let name = incomeAction == .start ? trimmed(incomeName) : selectedIncomeName
                guard !name.isEmpty else { throw ValidationError.invalid("Enter an income source name.") }
                if incomeAction == .start {
                    guard !activeStreams.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                        throw ValidationError.invalid("That source is already active. Choose Change to update its rate.")
                    }
                } else if selectedIncome == nil {
                    throw ValidationError.invalid("Choose an active income source. Ended sources are kept in history.")
                }
                let reason = try requiredReason(incomeReason)
                let amount: Int64? = incomeAction == .end ? nil : try parseAmount(monthlyAmount)
                if incomeAction != .end {
                    guard snapshot.accounts.contains(where: { $0.id == receivingAccountID }) else {
                        throw ValidationError.invalid("Choose a recorded account to receive this income.")
                    }
                    if incomeKind == .wage, incomeTier.isEmpty {
                        throw ValidationError.invalid("Choose a wage tier for this income source.")
                    }
                }
                let change = IncomeStreamChange(action: incomeAction, name: name,
                    kind: incomeAction == .end ? nil : incomeKind,
                    tier: incomeAction != .end && incomeKind == .wage ? incomeTier : nil,
                    monthlyMinor: amount, accountId: incomeAction == .end ? nil : receivingAccountID,
                    pathId: incomeAction != .end && !incomePathID.isEmpty ? incomePathID : nil,
                    effectiveFrom: snapshot.character.currentDate.iso, reason: reason)
                try model.updateFinances(accountOpenings: [], streamChanges: [change], transfers: [],
                    expectedLifeID: snapshot.character.id, expectedRevision: snapshot.revision)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func parseAmount(_ text: String) throws -> Int64 {
        let value = trimmed(text)
        let pattern = #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil,
              value.filter({ $0.isNumber }).count <= 38,
              var amount = Decimal(string: value.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN else {
            throw ValidationError.invalid("Enter a positive amount using a decimal point, such as 50,000.00, without a currency symbol.")
        }
        var units = Decimal(max(1, snapshot.economy.minorUnitsPerUnit))
        var minor = Decimal()
        guard NSDecimalMultiply(&minor, &amount, &units, .plain) == .noError,
              !minor.isNaN, minor > 0, minor <= Decimal(Int64.max) else {
            throw ValidationError.invalid("Enter a positive amount within the supported range.")
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &minor, 0, .plain)
        guard rounded == minor else {
            throw ValidationError.invalid("That amount includes a fraction smaller than this currency's smallest unit.")
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private func requiredReason(_ text: String) throws -> String {
        let reason = trimmed(text)
        guard !reason.isEmpty else { throw ValidationError.invalid("Enter a reason for this change.") }
        return reason
    }
    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func money(_ amount: Int64) -> String { Money.format(amount, economy: snapshot.economy) }
    private func accountLabel(_ id: String) -> String { snapshot.accounts.first(where: { $0.id == id })?.name ?? "Unknown account" }
    private func kindLabel(_ kind: IncomeStream.Kind) -> String {
        switch kind {
        case .wage: return "Wage"
        case .selfEmployment: return "Self-employment"
        case .business: return "Business profit"
        case .allowance: return "Allowance"
        case .rental: return "Rental income"
        }
    }
}
