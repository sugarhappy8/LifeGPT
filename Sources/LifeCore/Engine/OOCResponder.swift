/// Answers `((out-of-character))` questions exactly from the database. The AI
/// is never asked, so these answers cannot drift or be talked into anything.
public enum OOCResponder {
    static let help = "I can answer out-of-character questions about your balance, accounts, date and age, income, people, and decisions."

    public static func answer(_ question: String, store: LifeStore) throws -> String {
        let words = Set(question.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        func asks(_ keywords: [String]) -> Bool { keywords.contains { words.contains($0) } }

        if asks(["account", "accounts", "bank", "banking"]) {
            let economy = try store.economy()
            return try store.accounts().map { "\($0.name) [\($0.id)]: \(Money.format($0.balanceMinor, economy: economy))" }.joined(separator: "\n")
        }
        if asks(["balance", "money", "cash"]) {
            return "Balance: \(Money.format(try store.balanceMinor(), economy: try store.economy()))"
        }
        if asks(["date", "age", "old"]) {
            let c = try store.character()
            return "Date: \(c.currentDate.iso). Age: \(c.ageYears)."
        }
        if asks(["income", "job", "salary", "profit", "revenue", "earnings"]) {
            let economy = try store.economy()
            let lines = try store.incomeStreams().filter { $0.endedOn == nil }.map { stream in
                return "\(stream.name): \(Money.format(stream.monthlyMinor, economy: economy)) per month (\(stream.kind.rawValue)), paid to \(stream.accountId)"
            }
            return lines.isEmpty ? "No income streams." : lines.joined(separator: "\n")
        }
        if asks(["who", "people", "family", "friends"]) {
            let people = try store.castMembers().map { member in
                member.relation.map { "\(member.name) (\($0))" } ?? member.name
            }
            return people.isEmpty ? "People: none yet." : "People: " + people.joined(separator: ", ")
        }
        if asks(["decision", "decisions", "choice", "choices"]) {
            let decisions = try store.decisions(limit: 5).map { "\($0.summary) (\($0.choice))" }
            return decisions.isEmpty ? "Decisions: none yet." : "Decisions: " + decisions.joined(separator: "; ")
        }
        return help
    }
}
