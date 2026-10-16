import Foundation

/// All borrowing, ownership transfers, interest and missed bills are computed here.
/// Model-proposed direct loan, asset-sale and investment ledger entries remain forbidden.
public enum FinanceEngine {
    public struct Plan: Sendable {
        public var ledger: [NewLedgerEntry] = []
        public var positions: [FinancialPosition]
        public var accountBalances: [String: Int64]
        public var personalAccountId: String = "personal"
        /// Legacy actions and household bills use personal funds, never another account's cash.
        public var balance: Int64 {
            get { accountBalances[personalAccountId, default: 0] }
            set { accountBalances[personalAccountId] = newValue }
        }
        public var rejections: [String] = []
        public init(positions: [FinancialPosition], balance: Int64, accountBalances: [String: Int64]? = nil, personalAccountId: String = "personal") {
            self.personalAccountId = personalAccountId
            self.positions = positions; self.accountBalances = accountBalances ?? [personalAccountId: balance]
        }
    }

    public static func settle(to end: GameDate, character: Character, streams: [IncomeStream],
                              economy: EconomyCard, balance: Int64, positions: [FinancialPosition],
                              paths: [OpportunityPath], household: HouseholdSupport = .independent,
                              accounts: [BankAccount]? = nil, personalAccountId: String = "personal") throws -> Plan {
        var plan = Plan(positions: positions, balance: balance,
            accountBalances: accounts.map { Dictionary(uniqueKeysWithValues: $0.filter(\.isAccessible).map { ($0.id, $0.balanceMinor) }) }, personalAccountId: personalAccountId)
        let payroll = TimeEngine.plan(days: end.daysSince(character.currentDate), character: character, streams: streams.filter { plan.accountBalances[$0.accountId] != nil }, economy: economy, household: household, personalAccountId: personalAccountId)
        var boundary = GameDate(year: character.currentDate.year, month: character.currentDate.month, day: 1).adding(months: 1)
        while boundary <= end {
            for entry in payroll.filter({ $0.date == boundary && $0.amountMinor > 0 }) { try post(entry, to: &plan) }
            for path in paths where path.stage == .profit && path.stageStartedOn < boundary {
                // A recorded stream replaces the legacy fixed path payout, including after it ends.
                if streams.contains(where: { $0.startedOn <= boundary && ($0.pathId == path.id || ($0.kind == .business && $0.name.caseInsensitiveCompare(path.title) == .orderedSame)) }) { continue }
                try post(entry(.businessProfit, economy.medianMonthlyIncomeMinor / 2, "Profit from \(path.title)", boundary, accountId: personalAccountId), to: &plan)
            }
            for index in plan.positions.indices {
                let p = plan.positions[index]
                guard p.principalMinor > 0, p.openedOn < boundary, plan.accountBalances[p.accountId ?? personalAccountId] != nil else { continue }
                let interest = CheckedMoney.fraction(p.principalMinor, numerator: Int64(p.annualRateBPS), denominator: 120_000)
                if p.kind == .investment {
                    if interest > 0 { try post(entry(.investment, interest, "Interest from \(p.name)", boundary, accountId: p.accountId ?? "personal"), to: &plan) }
                } else if p.kind == .loan {
                    plan.positions[index].principalMinor = try CheckedMoney.add(p.principalMinor, interest)
                }
            }
            for entry in payroll.filter({ $0.date == boundary && $0.amountMinor < 0 }) { try post(entry, to: &plan) }
            for index in plan.positions.indices where plan.positions[index].kind == .loan {
                let p = plan.positions[index]
                let accountId = p.accountId ?? "personal"
                let paid = min(max(0, plan.accountBalances[accountId, default: 0]), min(p.monthlyPaymentMinor, p.principalMinor))
                if paid > 0 {
                    try post(entry(.expense, -paid, "Loan payment: \(p.name)", boundary, accountId: accountId), to: &plan)
                    plan.positions[index].principalMinor -= paid
                }
            }
            boundary = boundary.adding(months: 1)
        }
        return plan
    }

    public static func actions(_ actions: [FinancialAction], date: GameDate, age: Int, economy: EconomyCard,
                               streams: [IncomeStream], plan initial: Plan, household: HouseholdSupport = .independent) throws -> Plan {
        var plan = initial
        var borrowedThisTurn = false
        for action in actions.prefix(12) {
            let id = action.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = action.amountMinor
            let accountId = action.accountId ?? plan.personalAccountId
            let cash = plan.accountBalances[accountId, default: 0]
            func reject(_ reason: String) { plan.rejections.append("financial_actions \(name): \(reason)") }
            guard !id.isEmpty, id.count <= 100, !name.isEmpty, name.count <= 200,
                  amount > 0, amount <= 1_000_000_000_000, plan.accountBalances[accountId] != nil else {
                reject("needs a name, stable ID, known account and positive amount within 1 trillion minor units"); continue
            }
            let index = plan.positions.firstIndex { $0.id == id }
            if let index, (plan.positions[index].accountId ?? plan.personalAccountId) != accountId {
                reject("this position belongs to a different account"); continue
            }
            if [.buyAsset, .invest, .borrow].contains(action.action),
               id.hasPrefix("_engine_") || ["living-arrears", "fine-arrears"].contains(id) {
                reject("this ID is reserved for engine-recorded debt"); continue
            }
            switch action.action {
            case .buyAsset, .invest:
                guard age >= 18 else { reject("a guardian controls major purchases and investments before 18"); continue }
                guard index == nil, plan.positions.count < 100, cash >= amount else {
                    reject("ID already exists, portfolio is full, or savings cannot cover this purchase"); continue
                }
                let kind: FinancialPosition.Kind = action.action == .invest ? .investment : .asset
                plan.positions.append(FinancialPosition(id: id, name: name, kind: kind, principalMinor: amount,
                    annualRateBPS: kind == .investment ? (date.year >= 1900 ? 300 : 100) : 0, openedOn: date, accountId: accountId))
                try post(entry(.expense, -amount, "\(kind == .investment ? "Deposit into" : "Purchase of") \(name)", date, accountId: accountId), to: &plan)
            case .sellAsset, .withdraw:
                guard let index else { reject("you do not own this position"); continue }
                let p = plan.positions[index]
                guard (action.action == .sellAsset && p.kind == .asset) || (action.action == .withdraw && p.kind == .investment) else {
                    reject("wrong position type"); continue
                }
                guard amount <= p.principalMinor else { reject("amount exceeds the recorded principal or purchase value"); continue }
                // No model-assigned appreciation. This conservative v1 resale band is 80% of recorded purchase cost.
                let proceeds = p.kind == .asset ? CheckedMoney.fraction(amount, numerator: 80, denominator: 100) : amount
                plan.positions[index].principalMinor -= amount
                if proceeds > 0 { try post(entry(.assetSale, proceeds, "\(p.kind == .asset ? "Sale" : "Withdrawal"): \(p.name)", date, accountId: accountId), to: &plan) }
            case .borrow:
                let monthly = try streams.filter { TimeEngine.isActive($0, on: date) && $0.accountId == accountId }.reduce(Int64(0)) { try CheckedMoney.add($0, $1.monthlyMinor) }
                let spare = max(0, monthly - (accountId == plan.personalAccountId ? household.monthlyCost(economy: economy) : 0))
                guard age >= 18, !borrowedThisTurn, index == nil,
                      !plan.positions.contains(where: { $0.isDebt && $0.principalMinor > 0 && plan.accountBalances[$0.accountId ?? plan.personalAccountId] != nil }),
                      amount <= spare * 6, spare > 0 else {
                    reject("credit requires adult age, surplus recurring income, no outstanding debt, and at most six months of surplus income"); continue
                }
                let payment = max(1, amount / 12 + amount * 800 / 120_000)
                guard payment <= spare / 2 else { reject("monthly repayment exceeds half your surplus income"); continue }
                plan.positions.append(FinancialPosition(id: id, name: name, kind: .loan, principalMinor: amount,
                    annualRateBPS: 800, monthlyPaymentMinor: payment, openedOn: date, accountId: accountId))
                borrowedThisTurn = true
                try post(entry(.loan, amount, "Loan: \(name)", date, accountId: accountId), to: &plan)
            case .repay:
                guard let index, plan.positions[index].isDebt, plan.positions[index].principalMinor >= amount,
                      cash >= amount else { reject("repayment must be covered by savings and cannot exceed the debt"); continue }
                plan.positions[index].principalMinor -= amount
                try post(entry(.expense, -amount, "Debt repayment: \(name)", date, accountId: accountId), to: &plan)
            }
        }
        if actions.count > 12 { plan.rejections.append("At most twelve financial actions may happen in one turn.") }
        return plan
    }

    public static func applyCrime(_ outcome: CrimeEngine.Outcome, date: GameDate, to initial: Plan) throws -> Plan {
        var plan = initial
        if let rejection = outcome.rejection { plan.rejections.append(rejection); return plan }
        guard outcome.money != 0 else { return plan }
        if outcome.money > 0 { try post(entry(.crime, outcome.money, "Fate-gated proceeds from an offense", date, accountId: plan.personalAccountId), to: &plan) }
        else {
            let fine = -outcome.money
            let missing = max(0, fine - plan.balance)
            if missing > 0 {
                if let index = plan.positions.firstIndex(where: { $0.id == "fine-arrears" }) {
                    guard plan.positions[index].kind == .arrears else { throw ValidationError.invalid("The reserved fine-arrears position has an invalid type.") }
                    plan.positions[index].principalMinor = try CheckedMoney.add(plan.positions[index].principalMinor, missing)
                } else {
                    plan.positions.append(FinancialPosition(id: "fine-arrears", name: "Unpaid fines", kind: .arrears, principalMinor: missing, openedOn: date, accountId: plan.personalAccountId))
                }
                try post(entry(.loan, missing, "Fine carried as recorded debt", date, accountId: plan.personalAccountId), to: &plan)
            }
            try post(entry(.expense, -fine, "Fine following an offense", date, accountId: plan.personalAccountId), to: &plan)
        }
        return plan
    }

    /// Expenses beyond cash become explicit living-cost arrears, never an unexplained negative wallet.
    private static func post(_ entry: NewLedgerEntry, to plan: inout Plan) throws {
        guard let cash = plan.accountBalances[entry.accountId] else { throw ValidationError.invalid("Unknown account: \(entry.accountId)") }
        let next = try CheckedMoney.add(cash, entry.amountMinor)
        if next < 0 {
            guard entry.sourceType == .livingCost, entry.accountId == plan.personalAccountId else {
                throw ValidationError.invalid("Account \(entry.accountId) cannot cover this payment.")
            }
            let shortage = -next
            if let index = plan.positions.firstIndex(where: { $0.id == "living-arrears" }) {
                guard plan.positions[index].kind == .arrears else { throw ValidationError.invalid("The reserved living-arrears position has an invalid type.") }
                plan.positions[index].principalMinor = try CheckedMoney.add(plan.positions[index].principalMinor, shortage)
            } else {
                plan.positions.append(FinancialPosition(id: "living-arrears", name: "Unpaid living costs", kind: .arrears,
                                                       principalMinor: shortage, openedOn: entry.date, accountId: plan.personalAccountId))
            }
            plan.ledger.append(self.entry(.loan, shortage, "Living costs carried as recorded debt", entry.date, accountId: plan.personalAccountId))
            plan.balance = try CheckedMoney.add(plan.balance, shortage)
        }
        plan.ledger.append(entry)
        plan.accountBalances[entry.accountId] = try CheckedMoney.add(plan.accountBalances[entry.accountId, default: 0], entry.amountMinor)
    }
    public static func record(_ entries: [NewLedgerEntry], to initial: Plan) throws -> Plan {
        var plan = initial
        for entry in entries { try post(entry, to: &plan) }
        return plan
    }
    static func entry(_ source: SourceType, _ amount: Int64, _ reason: String, _ date: GameDate, accountId: String = "personal") -> NewLedgerEntry {
        NewLedgerEntry(date: date, sourceType: source, amountMinor: amount, reason: reason, counterparty: nil, origin: .engine, accountId: accountId)
    }
}
