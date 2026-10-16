import Foundation

public enum PathEngine {
    public struct Plan: Sendable {
        public var paths: [OpportunityPath]
        public var ledger: [NewLedgerEntry] = []
        public var rejections: [String] = []
    }
    public static func plan(_ changes: [PathUpdate], existing: [OpportunityPath], date: GameDate,
                            age: Int, economy: EconomyCard, balance: Int64, fate: Int,
                            playStyle: PlayStyle = .simulation, personalAccountId: String = "personal") -> Plan {
        var result = Plan(paths: existing)
        var cash = balance
        var seen = Set<String>()
        for update in changes.prefix(5) {
            let id = update.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            func reject(_ reason: String) { result.rejections.append("path \(update.title): \(reason)") }
            guard !id.isEmpty, id.count <= 100, !update.title.isEmpty, update.title.count <= 200,
                  update.notes.count <= 2000, seen.insert(id).inserted else { reject("invalid or repeated path"); continue }
            guard let index = result.paths.firstIndex(where: { $0.id == id }) else {
                guard (update.stage == .idea || playStyle == .sandbox), result.paths.filter({ $0.stage != .abandoned }).count < 3 else {
                    reject("a path must begin as an idea; at most three active paths"); continue
                }
                result.paths.append(OpportunityPath(id: id, title: update.title, stage: update.stage, startedOn: date, notes: update.notes)); continue
            }
            var path = result.paths[index]
            if update.stage == path.stage { path.notes = update.notes; result.paths[index] = path; continue }
            guard path.stage != .abandoned else { reject("an abandoned path cannot restart; create a new idea"); continue }
            if update.stage != .abandoned && playStyle == .simulation {
                guard age >= 18, update.stage.ordinal == path.stage.ordinal + 1 else {
                    reject("business stages require adult age and must advance one stage at a time"); continue
                }
                let requiredDays = [7, 30, 60, 90][min(path.stage.ordinal, 3)]
                guard date.daysSince(path.stageStartedOn) >= requiredDays else {
                    reject("this stage needs at least \(requiredDays) days"); continue
                }
                if update.stage == .capital {
                    let required = max(1, economy.medianMonthlyIncomeMinor / 2)
                    guard cash >= required else { reject("capital needs \(required) minor units of your own savings"); continue }
                    cash -= required; path.investedMinor += required
                    result.ledger.append(FinanceEngine.entry(.expense, -required, "Business capital: \(path.title)", date,
                        accountId: personalAccountId))
                }
                if update.stage == .launch || update.stage == .profit {
                    guard fate >= 40 else { reject("fate \(fate) delays this attempt; keep the current stage and try later"); continue }
                }
            }
            path.stage = update.stage; path.stageStartedOn = date; path.notes = update.notes
            result.paths[index] = path
        }
        if changes.count > 5 { result.rejections.append("Too many path changes in one turn.") }
        return result
    }
}
