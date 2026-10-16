import Foundation

public enum BankingEngine {
    public struct OpenPlan {
        public var accounts: [BankAccount]
        public var openings: [AccountOpening] = []
        public var rejections: [String] = []
    }
    public static func open(_ requests: [AccountOpening], existing: [BankAccount]) -> OpenPlan {
        var result = OpenPlan(accounts: existing)
        for request in requests.prefix(20) {
            let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard request.id.range(of: #"^[a-z0-9][a-z0-9_-]{0,79}$"#, options: .regularExpression) != nil,
                  !name.isEmpty, name.count <= 100, result.accounts.filter({ $0.status == .active }).count < 20,
                  !result.accounts.contains(where: { $0.id == request.id || $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                result.rejections.append("account_openings: use a unique lowercase ID and name, with at most 20 accounts"); continue
            }
            guard request.kind != .taxReserve else {
                result.rejections.append("tax-reserve accounts are created by the business engine"); continue
            }
            let opening = AccountOpening(id: request.id, name: name, kind: request.kind)
            result.openings.append(opening)
            result.accounts.append(BankAccount(id: opening.id, name: name, kind: opening.kind))
        }
        if requests.count > 20 { result.rejections.append("Too many account openings in one turn.") }
        return result
    }

    public static func transfer(_ requests: [AccountTransfer], date: GameDate, plan initial: FinanceEngine.Plan) throws -> FinanceEngine.Plan {
        var plan = initial
        for request in requests.prefix(30) {
            let reason = request.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard request.fromAccount != request.toAccount, plan.accountBalances[request.toAccount] != nil,
                  let available = plan.accountBalances[request.fromAccount],
                  request.amountMinor > 0, request.amountMinor <= 1_000_000_000_000,
                  request.amountMinor <= available, !reason.isEmpty, reason.count <= 1000 else {
                plan.rejections.append("transfers: select two different known accounts, a positive affordable amount and a concise reason"); continue
            }
            let pair = [
                NewLedgerEntry(date: date, sourceType: .transfer, amountMinor: -request.amountMinor, reason: reason,
                    counterparty: request.toAccount, origin: .engine, accountId: request.fromAccount),
                NewLedgerEntry(date: date, sourceType: .transfer, amountMinor: request.amountMinor, reason: reason,
                    counterparty: request.fromAccount, origin: .engine, accountId: request.toAccount)
            ]
            plan = try FinanceEngine.record(pair, to: plan)
        }
        if requests.count > 30 { plan.rejections.append("At most thirty transfers may happen in one turn.") }
        return plan
    }

    /// Manual record edits use the same validators and optimistic transaction as narrated changes.
    public static func manage(store: LifeStore, openings: [AccountOpening], changes: [IncomeStreamChange],
                              transfers: [AccountTransfer], expectedRevision: Int) throws {
        guard try store.revision() == expectedRevision else { throw ValidationError.invalid("This life changed. Reopen Manage finances before editing.") }
        let character = try store.character()
        let opened = open(openings, existing: try store.accounts())
        let income = IncomeEngine.plan(changes: changes, existing: try store.incomeStreams(), start: character.currentDate,
            end: character.currentDate, economy: try store.economy(), playStyle: try store.sessionSettings().playStyle,
            accounts: opened.accounts, paths: try store.paths(), personalAccountId: try store.businessSimulation().defaultPersonalAccountId)
        var plan = FinanceEngine.Plan(positions: [], balance: 0,
            accountBalances: Dictionary(uniqueKeysWithValues: opened.accounts.filter(\.isAccessible).map { ($0.id, $0.balanceMinor) }))
        plan = try transfer(transfers, date: character.currentDate, plan: plan)
        let errors = opened.rejections + income.rejections + plan.rejections
        guard errors.isEmpty else { throw ValidationError.invalid(errors.joined(separator: "\n")) }
        try store.applyFinancialChanges(accountOpenings: opened.openings, streamChanges: income.changes,
            ledger: plan.ledger, expectedRevision: expectedRevision)
    }
}
