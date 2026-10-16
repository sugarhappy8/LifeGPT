import SwiftUI
import LifeCore

struct NewLifeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var character = NewCharacter(name: "", birthplace: "", birthYear: 1995, appearance: "", startingAge: 18, background: "")
    @State private var storySettings = SessionSettings()
    @State private var draft = SetupDraft.manual(for: NewCharacter(name: "", birthplace: "", birthYear: 1995, appearance: "", startingAge: 18, background: nil))
    @State private var reviewing = false
    @State private var generating = false
    @State private var generated = false
    @State private var error: String?
    @State private var generation: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                LifeMark(size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(reviewing ? "The world before you" : "Who will you become?").font(.system(size: 29, design: .serif))
                    Text(reviewing ? "Review the setting, people, and economy before your life begins." : "A person, a place, a moment. The rest is still unwritten.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(reviewing ? "02 / 02" : "01 / 02").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(28)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if reviewing {
                        NoticeBar(text: generated ? "This is an AI-generated draft. Review its historical assumptions and prices; you can edit them below." : "Manual setup uses sample USD prices. Adjust the currency, amounts, and setting for this life before beginning.") {}
                        SetupReviewView(draft: $draft)
                        Divider()
                        SectionLabel(text: "Your own starting savings")
                        Text(Money.format(StartingMoney.balanceMinor(forAge: character.startingAge, economy: draft.economy), economy: draft.economy))
                            .font(.system(size: 25, design: .rounded))
                        Text("Family wealth shapes your upbringing. Your personal wallet begins with a small, age-appropriate amount.").font(.callout).foregroundStyle(.secondary)
                    } else { creationFields }
                    if let error { NoticeBar(text: error, isError: true) { self.error = nil } }
                }.padding(28)
            }
            Divider()
            HStack {
                Button(generating ? "Cancel generation" : "Cancel") {
                    if generating { generation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
                if reviewing { Button("Back") { reviewing = false } }
                Spacer()
                if generating { ProgressView().controlSize(.small); Text("Building your world…").font(.callout).foregroundStyle(.secondary) }
                else if reviewing {
                    Button("Begin this life") { begin() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    if model.settings.provider != .demo {
                        Button("Set up manually") { prepareManual() }.buttonStyle(.bordered)
                    }
                    Button(model.settings.provider == .demo ? "Review starting life" : "Generate setting") {
                        if model.settings.provider == .demo { prepareManual() } else { generate() }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }.frame(width: 690, height: 760).interactiveDismissDisabled(generating)
            .onDisappear { generation?.cancel() }
    }
    private var creationFields: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionLabel(text: "The essentials")
            HStack(spacing: 18) {
                labeled("Name") { TextField("Your character's name", text: $character.name) }
                labeled("Birthplace") { TextField("City, country", text: $character.birthplace) }
            }
            HStack(spacing: 18) {
                labeled("Birth year") { TextField("Year", value: $character.birthYear, format: .number.grouping(.never)) }
                labeled("Starting age") { Stepper(value: $character.startingAge, in: 0...99) { Text("\(character.startingAge) years old") } }
            }
            Text("Your story begins in \(((1...9000).contains(character.birthYear) ? character.birthYear + character.startingAge : 0).description). Birthdays are January 1.").font(.caption).foregroundStyle(.secondary)
            labeled("Physical description") { TextField("Appearance, style, distinguishing details…", text: $character.appearance, axis: .vertical).lineLimit(2...4) }
            labeled("Background · optional") {
                TextField("Family, personality, history, hopes. What has shaped this person?", text: Binding(get: { character.background ?? "" }, set: { character.background = $0 }), axis: .vertical).lineLimit(4...7)
            }
            Text("Your background is part of the starting story. For example: UAE royalty, living with my parents, or a first-generation student. Family resources and support are separate from your personal wallet.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            StoryControls(swing: $character.swingDial, words: $character.replyLengthWords, settings: $storySettings, compact: true)
        }.textFieldStyle(.roundedBorder).disabled(generating)
    }
    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(label).font(.caption.weight(.medium)); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func prepareManual() {
        do { try character.validate(); draft = .manual(for: character); generated = false; reviewing = true; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func generate() {
        do { try character.validate() } catch { self.error = error.localizedDescription; return }
        generating = true; error = nil
        generation = Task {
            defer { generating = false; generation = nil }
            do {
                let result = try await model.generateSetup(character)
                try Task.checkCancellation()
                draft = result; generated = true; reviewing = true
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func begin() {
        do { try model.createLife(character: character, setup: draft, storySettings: storySettings); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct SetupReviewView: View {
    @Binding var draft: SetupDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "Place & time")
            TextEditor(text: $draft.placeBrief).font(.callout).frame(minHeight: 120).padding(6).background(.background).clipShape(RoundedRectangle(cornerRadius: 8))
            Picker("Family wealth", selection: $draft.familyWealthTier) {
                ForEach(WealthTier.allCases, id: \.self) { Text($0 == .ultraWealthy ? "Ultra-wealthy" : $0.rawValue.capitalized).tag($0) }
            }
            Picker("Starting household", selection: Binding(get: {
                HouseholdSupport(rawValue: draft.lifeState.last(where: { $0.key == "household_support" })?.value ?? "") ?? .independent
            }, set: { support in
                draft.lifeState.removeAll { $0.key == "household_support" }
                draft.lifeState.append(LifeStateChange(key: "household_support", value: support.rawValue))
            })) {
                Text(HouseholdSupport.familySupported.label).tag(HouseholdSupport.familySupported)
                Text(HouseholdSupport.independent.label).tag(HouseholdSupport.independent)
            }
            Divider(); EconomyEditor(economy: $draft.economy)
            Divider(); SectionLabel(text: "The first people")
            ForEach(draft.cast.indices, id: \.self) { index in
                HStack {
                    TextField("Name", text: $draft.cast[index].name)
                    TextField("Relation", text: Binding(get: { draft.cast[index].relation ?? "" }, set: { draft.cast[index].relation = $0 }))
                    Button { draft.cast.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("Remove person")
                }
            }
            Button("Add a person") { draft.cast.append(CastUpdate(name: "", relation: "", notes: nil, status: "alive")) }.disabled(draft.cast.count >= 20)
            Divider(); SectionLabel(text: "Opening scene")
            TextEditor(text: $draft.opening).font(.system(size: 16, design: .serif)).frame(minHeight: 150)
        }.textFieldStyle(.roundedBorder)
    }
}

struct EconomyEditor: View {
    @Binding var economy: EconomyCard
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Economy")
            HStack {
                TextField("Currency code", text: $economy.currency).frame(width: 130)
                Picker("Smallest unit", selection: $economy.minorUnitsPerUnit) {
                    Text("Whole units").tag(1); Text("Tenths").tag(10); Text("Hundredths / cents").tag(100); Text("Thousandths").tag(1000)
                }
            }
            MoneyField(label: "Median monthly income", amount: $economy.medianMonthlyIncomeMinor, units: economy.minorUnitsPerUnit, currency: economy.currency)
            MoneyField(label: "Local monthly living costs", amount: $economy.monthlyLivingCostMinor, units: economy.minorUnitsPerUnit, currency: economy.currency)
            Text("Monthly wages by occupation tier").font(.caption.weight(.medium))
            ForEach(economy.wageBands.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 7) {
                    TextField("Tier name", text: $economy.wageBands[index].name).frame(width: 180)
                    HStack {
                        MoneyField(label: "From", amount: $economy.wageBands[index].minMonthlyMinor, units: economy.minorUnitsPerUnit, currency: economy.currency)
                        MoneyField(label: "To", amount: $economy.wageBands[index].maxMonthlyMinor, units: economy.minorUnitsPerUnit, currency: economy.currency)
                    }
                }
            }
        }.textFieldStyle(.roundedBorder)
    }
}

private struct MoneyField: View {
    let label: String
    @Binding var amount: Int64
    let units: Int
    let currency: String
    var body: some View {
        HStack {
            Text(label).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            TextField(label, value: Binding<Double>(get: { Double(amount) / Double(max(1, units)) }, set: { value in
                let minor = (value * Double(max(1, units))).rounded()
                if minor.isFinite, minor >= 0, minor <= 1_000_000_000_000 { amount = Int64(minor) }
            }), format: .number.precision(.fractionLength(0...3))).multilineTextAlignment(.trailing).frame(width: 120)
            Text(currency).font(.caption).foregroundStyle(.secondary)
        }
    }
}
