import SwiftUI
import LifeCore

struct StoryControls: View {
    @Binding var swing: Int
    @Binding var words: Int
    @Binding var settings: SessionSettings
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel(text: "How this life plays")
            Picker("Play style", selection: $settings.playStyle) {
                ForEach(PlayStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Text(settings.playStyle.explanation).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Difficulty").font(.callout.weight(.medium)); Spacer()
                Text(GameDifficulty.label(settings.difficulty)).font(.callout).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(settings.difficulty) }, set: { settings.difficulty = Int($0) }), in: 0...100, step: 5)
                .accessibilityLabel("Game difficulty").accessibilityValue("\(settings.difficulty), \(GameDifficulty.label(settings.difficulty))")
            HStack { Text("Forgiving"); Spacer(); Text("Challenging") }.font(.caption).foregroundStyle(.secondary)
            Text("Lower difficulty improves the odds of uncertain actions and encourages ambitious outcomes. At the easiest setting, success rolls gain 30 points; at the hardest, they lose 30. Balanced keeps the original odds.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Household", selection: $settings.household) {
                ForEach(HouseholdSupport.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text("When family covers your costs, automatic rent and living bills are zero. Follow the story uses your recorded living arrangement. A specific choice stays in effect until you change it.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Look up earlier records", selection: $settings.contextLookupMode) {
                ForEach(ContextLookupMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Text(settings.contextLookupMode.explanation + " Current dates, finances, relationships, and obligations are always included. Extra context requests use your selected model and count toward API usage; prose drafting is a separate setting.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            SectionLabel(text: "The way your story is told")
            Picker("Swing Dial", selection: $swing) {
                Text("Grounded").tag(0); Text("Heightened").tag(1); Text("Magical realist").tag(2); Text("Surreal").tag(3)
            }.pickerStyle(.segmented)
            Text(["An ordinary world, with all its small surprises.", "Dramatic coincidences and people you won't forget.", "Quiet impossibilities, treated as part of everyday life.", "Dream logic and unexpected changes of genre."][min(3, max(0, swing))])
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Reply length").font(.callout.weight(.medium)); Spacer()
                Text("About \(words) words").font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(words) }, set: { words = Int($0) }), in: 60...2000, step: 10)
            HStack(spacing: 10) {
                ForEach([80, 200, 500, 1000], id: \.self) { value in
                    Button([80: "Brief", 200: "Medium", 500: "Long", 1000: "Chapter"][value]!) { words = value }.buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
            }
            Toggle("Let length follow the scene", isOn: $settings.automaticLength).font(.callout)
            if !compact {
                Divider(); SectionLabel(text: "Voice Bible")
                Text("Describe tense, rhythm, perspective, and phrases to avoid. Leave blank for the default literary voice.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $settings.voiceBible).font(.callout).frame(minHeight: 140).padding(6).background(.background).clipShape(RoundedRectangle(cornerRadius: 8))
                TextField("Content tone", text: $settings.contentTone, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                Text("Sexual content involving anyone under 18 is never permitted. Tone settings do not change game rules.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct StorySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings: SessionSettings
    @State private var swing: Int
    @State private var words: Int
    @State private var error: String?
    init(snapshot: LifeSnapshot) {
        _settings = State(initialValue: snapshot.settings)
        _swing = State(initialValue: snapshot.character.swingDial)
        _words = State(initialValue: snapshot.character.replyLengthWords)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Life & story settings").font(.system(size: 28, design: .serif))
            ScrollView { StoryControls(swing: $swing, words: $words, settings: $settings).padding(.vertical, 8) }
            if let error { NoticeBar(text: error, isError: true) { self.error = nil } }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save for this life") {
                    do { try model.saveStorySettings(settings, swing: swing, words: words); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 610, height: 670)
    }
}

struct WorldEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var generating = false
    @State private var generation: Task<Void, Never>?
    private let snapshot: LifeSnapshot
    @State private var jurisdiction: JurisdictionRef?
    @State private var location: String
    @State private var economy: EconomyCard
    @State private var error: String?
    init(snapshot: LifeSnapshot) {
        self.snapshot = snapshot
        _jurisdiction = State(initialValue: snapshot.currentResidence)
        _text = State(initialValue: snapshot.world.last?.text ?? "Describe this life's place and era.")
        _location = State(initialValue: snapshot.state["residence"] ?? snapshot.world.last?.location ?? snapshot.character.birthplace)
        _economy = State(initialValue: snapshot.economy)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Place, time, and the price of things").font(.system(size: 26, design: .serif))
            Text("Update the setting after a move or a change of era. Every revision is kept. Existing balances stay in this life's accounting currency.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NationPickerView(selection: $jurisdiction, date: snapshot.character.currentDate)
                    HStack {
                        Text(location).font(.caption).foregroundStyle(.secondary)
                        if model.settings.provider != .demo {
                            Button(generating ? "Generating…" : "Generate updated draft") { generate() }.disabled(generating)
                        }
                    }
                    if generating { ProgressView().controlSize(.small) }
                    TextEditor(text: $text).font(.callout).frame(minHeight: 140)
                    EconomyEditor(economy: $economy)
                }
            }
            if let error { NoticeBar(text: error, isError: true) { self.error = nil } }
            HStack {
                Button(generating ? "Stop" : "Cancel") { if generating { generation?.cancel() } else { dismiss() } }.keyboardShortcut(.cancelAction); Spacer()
                Button("Save new version") {
                    do { guard let jurisdiction else { throw ValidationError.invalid("Select a preset country and region.") }
                        try model.updateWorld(text: text, location: location, economy: economy, jurisdiction: jurisdiction,
                            lifeID: snapshot.character.id, revision: snapshot.revision); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(generating)
            }
        }.padding(28).frame(width: 650, height: 720).interactiveDismissDisabled(generating)
             .onDisappear { generation?.cancel() }
            .onChange(of: jurisdiction) { _, ref in
                if let ref { location = CountryCatalog.shared.displayName(ref, on: snapshot.character.currentDate) }
            }
    }
    private func generate() {
        generating = true; error = nil
        generation = Task {
            defer { generating = false; generation = nil }
            do {
                let result = try await model.generateWorld(location: location, jurisdiction: jurisdiction)
                try Task.checkCancellation()
                text = result.brief; economy = result.economy
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

}
