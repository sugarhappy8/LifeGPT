import LifeGPTCore
import SwiftUI

/// Everything the AI reads each turn, shown to the player.
struct LifePanel: View {
    let state: GameState

    var body: some View {
        List {
            Section("Stats") {
                StatRow(label: "Health", value: state.stats.health, color: .red)
                StatRow(label: "Happiness", value: state.stats.happiness, color: .yellow)
                StatRow(label: "Smarts", value: state.stats.smarts, color: .blue)
                StatRow(label: "Looks", value: state.stats.looks, color: .pink)
            }
            Section("Money (\(state.world.currency))") {
                LabeledContent("Cash", value: formatMoney(state.finances.cash))
                LabeledContent("Income / yr", value: formatMoney(state.finances.annualIncome))
                LabeledContent("Expenses / yr", value: formatMoney(state.finances.annualExpenses))
                LabeledContent("Debt", value: formatMoney(state.finances.debt))
            }
            Section("About") {
                LabeledContent("Occupation", value: state.character.occupation)
                LabeledContent("Education", value: state.character.education)
                LabeledContent("Born", value: "\(state.character.birthDate.description), \(state.character.birthplace)")
                if !state.character.traits.isEmpty {
                    Text(state.character.traits.joined(separator: ", ")).foregroundStyle(.secondary)
                }
            }
            Section("People") {
                if state.relationships.isEmpty { Text("No one yet").foregroundStyle(.secondary) }
                ForEach(state.relationships) { person in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(person.name).fontWeight(.medium)
                            Spacer()
                            Text(person.status == .active ? "\(person.closeness)" : person.status.rawValue)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(person.relation).font(.caption).foregroundStyle(.secondary)
                    }
                    .help(person.notes.joined(separator: "\n"))
                }
            }
            Section("Major Moments") {
                if state.timeline.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(state.timeline.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).fontWeight(.medium)
                        Text("\(entry.date.description) · \(entry.summary)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value)").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(value), total: 100).tint(color)
        }
    }
}
