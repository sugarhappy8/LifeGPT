import SwiftUI
import LifeCore

struct ChatView: View {
    @Environment(AppModel.self) private var model
    let snapshot: LifeSnapshot
    @State private var showSkip = false
    @State private var showValidationDetails = false
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if snapshot.totalMessages > snapshot.messages.count {
                            Button("Load earlier chapters") { model.loadEarlier() }.buttonStyle(.plain).foregroundStyle(Color.lifeAccent).frame(maxWidth: .infinity)
                        }
                        ForEach(snapshot.messages, id: \.id) { message in
                            MessageView(message: message, readingSize: model.settings.readingSize).id(message.id)
                        }
                        if let pending = model.pendingText {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(pending).font(.system(size: 15)).padding(16).background(Color.lifeAccent.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Your story is taking shape…").font(.callout).foregroundStyle(.secondary) }
                            }
                        }
                        if snapshot.ended {
                            VStack(spacing: 12) {
                                Image(systemName: "leaf").font(.title2).foregroundStyle(Color.lifeAccent)
                                Text("A life, remembered.").font(.system(size: 25, design: .serif))
                                Text("This story has ended. Its memories remain yours.").font(.callout).foregroundStyle(.secondary)
                                Button("Begin another life") { model.showNewLife = true }.buttonStyle(.bordered)
                            }.frame(maxWidth: .infinity).padding(.vertical, 35)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: 740).padding(.horizontal, 34).padding(.vertical, 30).frame(maxWidth: .infinity)
                }
                .onChange(of: snapshot.messages.last?.id) { _, _ in withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: model.pendingText) { _, _ in withAnimation { scroll.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: model.selection) { _, _ in scroll.scrollTo("bottom", anchor: .bottom) }
                .onAppear { scroll.scrollTo("bottom", anchor: .bottom) }
            }
            if let error = model.error {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        NoticeBar(text: error, isError: true) { model.dismissError() }
                        HStack {
                            if model.canRetry {
                                Button("Retry reply") { model.retryTurn() }.buttonStyle(.bordered)
                                    .help("Retry the same action, time skip, and reply length")
                            }
                            if !model.validationDetails.isEmpty {
                                Button("Validation details") { showValidationDetails = true }.buttonStyle(.plain).font(.caption)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 110).padding(.horizontal, 20).padding(.bottom, 8)
            }
            if let information = model.information { NoticeBar(text: information) { model.information = nil }.padding(.horizontal, 20).padding(.bottom, 8) }
            if !snapshot.ended { composer }
        }
        .sheet(isPresented: $showSkip) { SkipTimeView(snapshot: snapshot).environment(model) }
        .alert("Validation details", isPresented: $showValidationDetails) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.validationDetails.joined(separator: "\n\n"))
        }
        .onChange(of: model.error) { _, _ in showValidationDetails = false }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.character.name).font(.system(size: 25, weight: .regular, design: .serif))
                Text(snapshot.state["residence"] ?? snapshot.character.birthplace).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(snapshot.character.currentDate.iso)  ·  Age \(snapshot.character.ageYears)").font(.system(size: 12, weight: .medium, design: .monospaced))
                Button { model.inspectorTab = .finances; model.showInspector = true } label: {
                    Text("\(Money.format(snapshot.balance, economy: snapshot.economy))\(snapshot.accounts.count > 1 ? " total" : "")").font(.system(size: 13, weight: .semibold, design: .monospaced))
                }.buttonStyle(.plain).foregroundStyle(Color.lifeAccent).help("Open finances")
                Button { model.inspectorTab = .finances; model.showInspector = true } label: {
                    Text("Legacy net: \(Money.format(snapshot.monthlyIncome, economy: snapshot.economy))/mo · Company gross: \(Money.format(snapshot.monthlyTotal(.revenue), economy: snapshot.economy))/mo").font(.caption)
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Check recurring income and destination accounts")
            }
        }.padding(.horizontal, 28).padding(.vertical, 18)
    }
    private var composer: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            if model.settings.showSuggestions, !model.busy, !snapshot.choices.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(snapshot.choices.enumerated()), id: \.offset) { _, choice in
                            Button { model.composer = choice } label: {
                                Text(choice).font(.caption).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 7)
                            }.buttonStyle(.plain).background(Color.primary.opacity(0.035)).clipShape(Capsule())
                        }
                    }
                }
            }
            VStack(spacing: 10) {
                TextField("What do you do, say, or dream of?", text: $model.composer, axis: .vertical)
                    .font(.system(size: 15)).lineLimit(2...6).textFieldStyle(.plain).disabled(model.busy)
                    .accessibilityLabel("Your next action")
                HStack(spacing: 10) {
                    Button { showSkip = true } label: { Label("Skip time", systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain).font(.caption).disabled(model.busy)
                    Picker("Reply length", selection: $model.quickLength) {
                        Text("Default length").tag(0); Text("Brief · 80 words").tag(80); Text("Medium · 200").tag(200)
                        Text("Long · 500").tag(500); Text("Chapter · 1000").tag(1000)
                    }.labelsHidden().frame(width: 150).controlSize(.small).disabled(model.busy).help("Override length for the next reply")
                    Spacer()
                    if model.busy {
                        Button { model.cancelTurn() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.bordered)
                    } else {
                        Button { model.send() } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).padding(4) }
                            .buttonStyle(.borderedProminent).disabled(!model.canSend).keyboardShortcut(.return, modifiers: .command)
                            .accessibilityLabel("Send action").help("Send (⌘ Return)")
                    }
                }
            }.padding(14).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
            HStack {
                Text(model.settings.provider == .demo ? "Offline demo · built-in scenes" : model.providerLabel + " · " + model.settings.model).lineLimit(1)
                Spacer()
                Text("⌘↵ to send · ((balance)) for facts")
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 12)
    }
}

private struct MessageView: View {
    let message: ChatMessage
    let readingSize: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionLabel(text: message.role == .player ? "You" : "The story")
                Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 22, height: 1)
                Text(message.date.iso).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                Spacer()
            }
            Text(message.text)
                .font(.system(size: message.role == .narrator ? readingSize : readingSize - 2, weight: .regular, design: message.role == .narrator ? .serif : .default))
                .lineSpacing(message.role == .narrator ? 7 : 4).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(message.role == .player ? 16 : 0)
            .background(message.role == .player ? Color.lifeAccent.opacity(0.065) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contextMenu { Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } }
    }
}

private struct SkipTimeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let snapshot: LifeSnapshot
    @State private var amount = 1
    @State private var unit = TimeAdvance.Unit.months
    @State private var focus = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Let time pass").font(.system(size: 28, design: .serif))
            Text("Your income, living costs, investments, and debt continue through the time you skip.").foregroundStyle(.secondary)
            HStack {
                Stepper(value: $amount, in: 1...maximum) { Text(amount.description).monospacedDigit().frame(width: 40) }
                Picker("Period", selection: $unit) { Text("Days").tag(TimeAdvance.Unit.days); Text("Months").tag(TimeAdvance.Unit.months); Text("Years").tag(TimeAdvance.Unit.years) }.frame(width: 140)
            }
            TextField("What do you focus on during this time?", text: $focus).textFieldStyle(.roundedBorder)
            Text("Next date: \(snapshot.character.currentDate.adding(TimeAdvance(unit: unit, amount: min(amount, maximum))).iso)").font(.callout).monospacedDigit()
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Continue") {
                let time = TimeAdvance(unit: unit, amount: min(amount, maximum))
                let period = time.amount == 1 ? String(unit.rawValue.dropLast()) : unit.rawValue
                model.send("I let \(time.amount) \(period) pass. " + (focus.isEmpty ? "I continue my everyday life." : focus), skipTime: time)
                dismiss()
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 460)
        .onChange(of: unit) { _, _ in amount = min(amount, maximum) }
    }
    private var maximum: Int { unit == .years ? 20 : unit == .months ? 240 : 7300 }
}
