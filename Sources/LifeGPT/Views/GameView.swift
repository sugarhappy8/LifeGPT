import LifeGPTCore
import SwiftUI

struct GameView: View {
    @EnvironmentObject var model: AppModel
    let state: GameState
    @State private var customAction = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(state.turns) { turn in
                            TurnCard(turn: turn).id(turn.id)
                        }
                        if model.isWorking {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(model.statusText).foregroundStyle(.secondary)
                            }
                            .id("working")
                        }
                        if state.isDead {
                            Text("\(state.character.name) died in \(state.world.currentDate.description), aged \(state.age). Cause: \(state.causeOfDeath ?? "unknown").")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: state.turns.count) {
                    if let last = state.turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .top) } }
                }
                .onChange(of: model.isWorking) {
                    if model.isWorking { withAnimation { proxy.scrollTo("working", anchor: .bottom) } }
                }
            }
            if !state.isDead {
                Divider()
                actionBar
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.character.name).font(.title2.bold())
            Text("Age \(state.age)").foregroundStyle(.secondary)
            Spacer()
            Text("\(state.world.currentDate.description) · \(state.world.location)")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.pendingChoices.isEmpty {
                FlowChoices(choices: state.pendingChoices) { choice in
                    Task { await model.play(choice) }
                }
            }
            HStack {
                TextField("Do something else...", text: $customAction)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitCustom)
                Button("Do It", action: submitCustom)
                    .disabled(customAction.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Skip Ahead") { Task { await model.play("Skip ahead a year or so; live day to day.") } }
            }
        }
        .disabled(model.isWorking)
        .padding(16)
    }

    private func submitCustom() {
        let action = customAction.trimmingCharacters(in: .whitespaces)
        guard !action.isEmpty else { return }
        customAction = ""
        Task { await model.play(action) }
    }
}

struct FlowChoices: View {
    let choices: [String]
    let onPick: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { buttons }
            VStack(alignment: .leading) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(choices, id: \.self) { choice in
            Button(choice) { onPick(choice) }
                .buttonStyle(.bordered)
        }
    }
}

struct TurnCard: View {
    let turn: TurnRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(turn.dateBefore == turn.dateAfter ? turn.dateAfter.description : "\(turn.dateBefore.description) → \(turn.dateAfter.description)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("› \(turn.playerAction)")
                .font(.callout.italic())
                .foregroundStyle(.secondary)
            Text(turn.narration)
                .font(.system(.body, design: .serif))
                .lineSpacing(3)
                .textSelection(.enabled)
            if !turn.events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(turn.events.enumerated()), id: \.offset) { _, event in
                        Label {
                            Text("**\(event.title)** · \(event.description)")
                        } icon: {
                            Image(systemName: EventIcon.name(for: event.category))
                        }
                        .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if !turn.changeLog.isEmpty {
                Text(turn.changeLog.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum EventIcon {
    static func name(for category: String) -> String {
        switch category.lowercased() {
        case "health": return "cross.case"
        case "family": return "house"
        case "career": return "briefcase"
        case "money": return "dollarsign.circle"
        case "romance": return "heart"
        case "friendship": return "person.2"
        case "education": return "graduationcap"
        case "world": return "globe"
        case "accident": return "exclamationmark.triangle"
        case "opportunity": return "sparkles"
        default: return "star"
        }
    }
}
