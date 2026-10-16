import SwiftUI
import LifeCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AppSettings()
    @State private var key = ""
    @State private var message: String?
    @State private var failed = false
    @State private var testing = false
    @State private var tab = "narrator"
    @State private var testTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                narrator.tabItem { Label("Narrator", systemImage: "text.bubble") }.tag("narrator")
                appearance.tabItem { Label("Reading", systemImage: "textformat") }.tag("reading")
                usage.tabItem { Label("Usage & storage", systemImage: "chart.bar") }.tag("usage")
            }.padding(20)
            if let message { NoticeBar(text: message, isError: failed) { self.message = nil }.padding(.horizontal, 20).padding(.bottom, 12) }
            Divider()
            HStack {
                Text("Settings apply across all lives.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(testing)
                Button("Save Settings") {
                    do { try model.saveSettings(draft, key: draft.usesCloud ? key : nil); dismiss() }
                    catch { failed = true; message = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || testing)
            }.padding(18)
        }.frame(width: 690, height: 720)
        .onAppear { draft = model.settings; loadKey() }
        .onChange(of: draft.provider) { _, _ in loadKey(); message = nil }
        .onDisappear { testTask?.cancel() }
        .task { await model.refreshUsage() }
    }
    private var narrator: some View {
        Form {
            Section {
                Picker("Provider", selection: $draft.provider) { ForEach(AppSettings.Provider.allCases) { Text($0.title).tag($0) } }
                switch draft.provider {
                case .demo:
                    Text("Explore the interface with a small collection of built-in scenes. For open-ended storytelling, connect a cloud provider or a model running on your computer.").font(.callout).foregroundStyle(.secondary)
                case .anthropic:
                    TextField("Model ID", text: $draft.anthropicModel)
                    SecureField("API key", text: $key).privacySensitive()
                    Toggle("Use two-step narration", isOn: $draft.cloudTwoStep)
                case .gemini:
                    TextField("Model ID", text: $draft.geminiModel)
                    SecureField("API key", text: $key).privacySensitive()
                    Toggle("Use two-step narration", isOn: $draft.cloudTwoStep)
                case .local:
                    TextField("Server URL", text: $draft.localServer)
                    HStack {
                        Button("LM Studio") { draft.localServer = "http://localhost:1234/v1" }
                        Button("Ollama") { draft.localServer = "http://localhost:11434/v1" }
                    }.controlSize(.small)
                    TextField("Loaded model name", text: $draft.localModel)
                    TextField("Context window (tokens)", value: $draft.contextTokens, format: .number.grouping(.never))
                    Toggle("Two-step narration", isOn: $draft.localTwoStep)
                    Toggle("Server supports JSON Schema output", isOn: $draft.localStructuredOutput)
                    Text("Start your server and load an instruction-tuned model first. Match the context window to the server's configured size; 32k or more leaves room for a longer life. No API key is sent.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(testing ? "Testing…" : "Test connection") { test() }.disabled(testing || model.busy)
                    if testing { ProgressView().controlSize(.small); Button("Stop") { testTask?.cancel() } }
                }
                if draft.usesCloud { Text("Testing sends a small request to this provider. API keys are saved in macOS Keychain. Story context is sent only to the provider you select.").font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Choose your narrator") }
            if draft.usesCloud {
                Section {
                    TextField("Estimated daily limit (USD; 0 = none)", value: $draft.dailyLimitUSD, format: .number.precision(.fractionLength(0...2)))
                    TextField("Input USD per million tokens", value: $draft.inputUSDPerMillion, format: .number.precision(.fractionLength(0...4)))
                    TextField("Output USD per million tokens", value: $draft.outputUSDPerMillion, format: .number.precision(.fractionLength(0...4)))
                    Text("Enter the rates for your selected model. These are editable estimates, not a live price feed. The limit reserves room for each request's maximum output, including setup and repairs. Your provider's invoice remains authoritative.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Spending estimate") }
            }
        }.formStyle(.grouped).disabled(model.busy)
    }
    private var appearance: some View {
        Form {
            Section("Reading") {
                Picker("Appearance", selection: $draft.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                HStack { Text("Story text size"); Slider(value: $draft.readingSize, in: 14...24, step: 1); Text("\(Int(draft.readingSize)) pt").monospacedDigit().frame(width: 45) }
                Toggle("Show suggested actions", isOn: $draft.showSuggestions)
            }
            Section("Preview") {
                Text("The day offers small things: a familiar face, a conversation you almost join. At the next turning you pause, aware that choosing a direction is still a choice.")
                    .font(.system(size: draft.readingSize, design: .serif)).lineSpacing(7).padding(.vertical, 10)
            }
            Section {
                Text("Voice, reply length, and the Swing Dial belong to each life. Open Story Settings from the chat toolbar to change them.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var usage: some View {
        Form {
            Section("Today") {
                LabeledContent("Estimated spending", value: model.todayCost.formatted(.currency(code: "USD")))
                LabeledContent("Requests", value: model.usage.filter { Calendar.current.isDateInToday($0.date) }.count.description)
                let lookups = model.usage.filter { Calendar.current.isDateInToday($0.date) && $0.purpose == "Context selection" }
                LabeledContent("Context selection (additional requests)", value: "\(lookups.count) · $\(lookups.reduce(0) { $0 + $1.estimatedUSD }.formatted(.number.precision(.fractionLength(4)))) estimated")
                Text("Every completed provider response is recorded, including setup, connection tests, corrections, and output that failed validation. Local/demo calls do not incur API charges.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Recent requests") {
                if model.usage.isEmpty { Text("No cloud requests recorded.").foregroundStyle(.secondary) }
                ForEach(model.usage.suffix(15).reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text((entry.purpose.map { $0 + " · " } ?? "") + entry.model).lineLimit(1); Spacer(); Text(entry.estimatedUSD.formatted(.currency(code: "USD").precision(.fractionLength(4)))) }
                        Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.inputTokens.grouped) in / \(entry.outputTokens.grouped) out").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("On this Mac") {
                Text(model.paths?.root.path ?? "Storage unavailable").font(.caption).textSelection(.enabled)
                HStack { Button("Show saves in Finder") { model.revealSaves() }; Button("Import a life…") { model.importLife() }.disabled(model.busy) }
                Text("Each life is its own SQLite save. Use Export Save for a portable backup, or Export Story for a readable transcript.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func loadKey() {
        do { key = draft.usesCloud ? try KeychainStore.read(draft.provider.rawValue) : "" }
        catch { key = ""; failed = true; message = error.localizedDescription }
    }
    private func test() {
        testing = true; message = nil
        testTask = Task {
            defer { testing = false; testTask = nil }
            do { message = try await model.testConnection(config: draft, key: key); failed = false }
            catch is CancellationError { message = "Connection test cancelled."; failed = false }
            catch { message = error.localizedDescription; failed = true }
            await model.refreshUsage()
        }
    }
}
