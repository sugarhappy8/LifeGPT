import Foundation

/// Applies an AI turn to the local game state. The game, not the AI, owns the numbers:
/// deltas are clamped, time only moves forward, and income accrues deterministically.
public enum StateApplier {
    public static let maxMonthsPerTurn = 120
    static let maxNotesPerRelationship = 6

    @discardableResult
    public static func apply(_ result: TurnResult, playerAction: String, to state: inout GameState) -> TurnRecord {
        let before = state.world.currentDate
        let months = min(max(result.monthsElapsed, 0), maxMonthsPerTurn)
        var log: [String] = []

        // Time and automatic money flow for the elapsed period.
        state.world.currentDate = before.adding(months: months)
        let accrual = (state.finances.annualIncome - state.finances.annualExpenses) * Double(months) / 12
        state.finances.cash += accrual
        if months > 0, accrual != 0 { log.append("Income and expenses \(formatMoney(accrual, signed: true))") }

        // Stats.
        let s = result.statChanges
        apply(s.health, to: &state.stats.health, label: "Health", log: &log)
        apply(s.happiness, to: &state.stats.happiness, label: "Happiness", log: &log)
        apply(s.smarts, to: &state.stats.smarts, label: "Smarts", log: &log)
        apply(s.looks, to: &state.stats.looks, label: "Looks", log: &log)

        // Finances.
        let f = result.financeChanges
        if f.oneOffCash != 0 {
            state.finances.cash += f.oneOffCash
            log.append("Cash \(formatMoney(f.oneOffCash, signed: true))")
        }
        if f.annualIncomeChange != 0 {
            state.finances.annualIncome = max(0, state.finances.annualIncome + f.annualIncomeChange)
            log.append("Income now \(formatMoney(state.finances.annualIncome))/yr")
        }
        if f.annualExpensesChange != 0 {
            state.finances.annualExpenses = max(0, state.finances.annualExpenses + f.annualExpensesChange)
            log.append("Expenses now \(formatMoney(state.finances.annualExpenses))/yr")
        }
        if f.debtChange != 0 {
            state.finances.debt = max(0, state.finances.debt + f.debtChange)
            log.append("Debt now \(formatMoney(state.finances.debt))")
        }

        // Identity and place.
        if let v = nonEmpty(result.newOccupation), v != state.character.occupation {
            state.character.occupation = v
            log.append("Occupation: \(v)")
        }
        if let v = nonEmpty(result.newEducation), v != state.character.education {
            state.character.education = v
            log.append("Education: \(v)")
        }
        if let v = nonEmpty(result.newLocation), v != state.world.location {
            state.world.location = v
            log.append("Moved to \(v)")
        }
        for trait in result.newTraits.compactMap(nonEmpty) where !state.character.traits.contains(where: { $0.caseInsensitiveCompare(trait) == .orderedSame }) {
            state.character.traits.append(trait)
        }

        // People.
        for change in result.relationshipChanges {
            guard let name = nonEmpty(change.name) else { continue }
            if let i = state.relationships.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                var r = state.relationships[i]
                r.closeness = clamp(r.closeness + change.closenessChange)
                if let rel = nonEmpty(change.relation) { r.relation = rel }
                if let status = Relationship.Status(rawValue: change.status), status != r.status {
                    r.status = status
                    log.append("\(name): \(status.rawValue)")
                }
                if let note = nonEmpty(change.note) { r.notes.append(note) }
                r.notes = Array(r.notes.suffix(maxNotesPerRelationship))
                state.relationships[i] = r
            } else {
                let status = Relationship.Status(rawValue: change.status) ?? .active
                let r = Relationship(
                    name: name,
                    relation: nonEmpty(change.relation) ?? "acquaintance",
                    closeness: clamp(50 + change.closenessChange),
                    status: status,
                    notes: nonEmpty(change.note).map { [$0] } ?? []
                )
                state.relationships.append(r)
                log.append("Met \(name) (\(r.relation))")
            }
        }

        // Memory.
        for entry in result.timelineEntries {
            guard let title = nonEmpty(entry.title) else { continue }
            state.timeline.append(TimelineEntry(
                date: state.world.currentDate,
                title: title,
                summary: entry.summary,
                importance: min(max(entry.importance, 1), 5)
            ))
        }

        if result.died {
            state.isDead = true
            state.causeOfDeath = nonEmpty(result.causeOfDeath) ?? "Unknown"
            state.stats.health = 0
            log.append("Died: \(state.causeOfDeath!)")
        }

        state.pendingChoices = state.isDead ? [] : Array(result.choices.compactMap(nonEmpty).prefix(4))

        let record = TurnRecord(
            dateBefore: before,
            dateAfter: state.world.currentDate,
            playerAction: playerAction,
            narration: result.narration,
            events: result.events,
            changeLog: log
        )
        state.turns.append(record)
        state.updatedAt = Date()
        return record
    }

    private static func apply(_ delta: Int, to value: inout Int, label: String, log: inout [String]) {
        guard delta != 0 else { return }
        let old = value
        value = clamp(value + delta)
        if value != old { log.append("\(label) \(value - old > 0 ? "+" : "")\(value - old)") }
    }

    static func clamp(_ v: Int) -> Int { min(max(v, 0), 100) }

    static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public func formatMoney(_ amount: Double, signed: Bool = false) -> String {
    let rounded = Int(amount.rounded())
    let digits = String(abs(rounded))
    var grouped = ""
    for (i, ch) in digits.reversed().enumerated() {
        if i > 0, i % 3 == 0 { grouped.append(",") }
        grouped.append(ch)
    }
    let body = "$" + String(grouped.reversed())
    if rounded < 0 { return "-" + body }
    return signed ? "+" + body : body
}
