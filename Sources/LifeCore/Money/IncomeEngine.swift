import Foundation

/// Validates recurring income and builds dated versions for monthly settlement.
/// A change never rewrites the rate that applied before its effective date.
public enum IncomeEngine {
    public static let maximumActiveStreams = 20
    public static let maximumMonthlyMinor: Int64 = 1_000_000_000_000
    public static let maximumChangesPerTurn = 40

    public struct Plan: Sendable {
        public var streams: [IncomeStream]
        public var changes: [IncomeStreamChange] = []
        public var rejections: [String] = []
    }

    public static func plan(changes: [IncomeStreamChange], existing: [IncomeStream],
                            start: GameDate, end: GameDate, economy: EconomyCard,
                            playStyle: PlayStyle, accounts: [BankAccount],
                            paths: [OpportunityPath], rules: MoneyRules = .v1, personalAccountId: String = "personal") -> Plan {
        var plan = Plan(streams: existing)
        guard end >= start else {
            plan.rejections.append("income_streams: effective dates require a nonnegative turn duration")
            return plan
        }
        var seen = Set<String>()
        var dated: [(index: Int, date: GameDate, change: IncomeStreamChange)] = []
        for (index, original) in changes.enumerated() {
            let change = normalized(original)
            func reject(_ reason: String) { plan.rejections.append("income_streams \(change.name): \(reason)") }
            guard index < maximumChangesPerTurn else {
                reject("at most \(maximumChangesPerTurn) income changes may happen in one turn"); continue
            }
            guard !change.name.isEmpty, change.name.count <= 200 else {
                reject("a stream needs a name of at most 200 characters"); continue
            }
            guard seen.insert(key(change.name)).inserted else {
                reject("only one change per stream is allowed in a turn"); continue
            }
            let date: GameDate
            if let supplied = change.effectiveFrom {
                guard let parsed = GameDate(iso: supplied), parsed.iso == supplied else {
                    reject("effective_from must be a valid YYYY-MM-DD date"); continue
                }
                date = parsed
            } else {
                date = end
            }
            guard date >= start, date <= end else {
                reject("effective_from must fall between \(start.iso) and \(end.iso)"); continue
            }
            dated.append((index, date, change))
        }

        // Closing streams first at a shared boundary permits a replacement without
        // temporarily exceeding the limit or paying both sources on that date.
        dated.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            if priority($0.change.action) != priority($1.change.action) {
                return priority($0.change.action) < priority($1.change.action)
            }
            return $0.index < $1.index
        }
        for item in dated {
            var change = item.change
            let date = item.date
            let active = plan.streams.filter { isActive($0, on: date) }
            let index = plan.streams.lastIndex { key($0.name) == key(change.name) && isActive($0, on: date) }
            let current = index.map { plan.streams[$0] }
            func reject(_ reason: String) { plan.rejections.append("income_streams \(change.name): \(reason)") }
            if let problem = problem(change, current: current, activeCount: active.count,
                                     economy: economy, rules: rules, playStyle: playStyle) {
                reject(problem); continue
            }
            change.effectiveFrom = date.iso
            if let current { change.name = current.name }
            if change.action == .end {
                if let index { plan.streams[index].endedOn = date }
                change.kind = nil; change.tier = nil; change.monthlyMinor = nil
                change.accountId = nil; change.pathId = nil
                plan.changes.append(change)
                continue
            }
            let projected = resolved(change, current: current, date: date, personalAccountId: personalAccountId)
            guard accounts.contains(where: { $0.id == projected.accountId && $0.isAccessible && ($0.openedOn == nil || $0.openedOn! <= date) }) else {
                reject("income destination account does not exist: \(projected.accountId)"); continue
            }
            if let pathId = projected.pathId {
                guard projected.kind == .business else {
                    reject("only business income can link to an opportunity path"); continue
                }
                guard paths.contains(where: { $0.id == pathId && $0.stage != .abandoned }) else {
                    reject("the linked opportunity path must exist and remain active"); continue
                }
                guard !active.contains(where: { $0.pathId == pathId && key($0.name) != key(projected.name) }) else {
                    reject("this opportunity path already has an active income stream"); continue
                }
            }
            // Reject overlaps even if an imported timeline has a future version.
            if change.action == .start, plan.streams.contains(where: {
                key($0.name) == key(change.name) && ($0.endedOn == nil || $0.endedOn! > date)
            }) {
                reject("a stream named \(change.name) already overlaps this period"); continue
            }
            if let index { plan.streams[index].endedOn = date }
            plan.streams.append(projected)
            change.kind = projected.kind
            change.tier = projected.tier
            change.monthlyMinor = projected.monthlyMinor
            change.accountId = projected.accountId
            change.pathId = projected.pathId
            plan.changes.append(change)
        }
        return plan
    }

    /// Compatibility validation for callers without dates or account context.
    /// The planner applies these same rules before checking timing and routing.
    static func validate(_ changes: [IncomeStreamChange], existing: [IncomeStream],
                         economy: EconomyCard, rules: MoneyRules, playStyle: PlayStyle) -> [MoneyVerdict] {
        var active = existing.filter { $0.endedOn == nil }
        var seen = Set<String>()
        return changes.enumerated().map { index, original in
            let change = normalized(original)
            guard index < maximumChangesPerTurn else {
                return .rejected("at most \(maximumChangesPerTurn) income changes may happen in one turn")
            }
            guard seen.insert(key(change.name)).inserted else {
                return .rejected("only one change per stream is allowed in a turn")
            }
            let currentIndex = active.firstIndex { key($0.name) == key(change.name) }
            let current = currentIndex.map { active[$0] }
            if let issue = problem(change, current: current, activeCount: active.count,
                                   economy: economy, rules: rules, playStyle: playStyle) {
                return .rejected(issue)
            }
            if let currentIndex { active.remove(at: currentIndex) }
            if change.action != .end {
                active.append(resolved(change, current: current,
                                       date: current?.startedOn ?? GameDate(year: 2000, month: 1, day: 1)))
            }
            return .accepted
        }
    }

    private static func problem(_ change: IncomeStreamChange, current: IncomeStream?, activeCount: Int,
                                economy: EconomyCard, rules: MoneyRules, playStyle: PlayStyle) -> String? {
        guard !change.name.isEmpty, change.name.count <= 200 else { return "a stream needs a name of at most 200 characters" }
        if change.action == .start {
            if current != nil { return "a stream named \(change.name) is already active" }
            if activeCount >= maximumActiveStreams { return "at most \(maximumActiveStreams) income streams may be active" }
        } else if current == nil { return "unknown stream: \(change.name)" }
        if change.action == .end { return nil }
        guard let monthly = change.monthlyMinor ?? current?.monthlyMinor else { return "missing monthly amount" }
        guard monthly > 0, monthly <= maximumMonthlyMinor else {
            return "monthly income must be positive and at most \(maximumMonthlyMinor) minor units"
        }
        let kind = change.kind ?? current?.kind ?? .wage
        let rationale = change.reason ?? ""
        guard rationale.count <= 1000 else { return "the income rationale must be at most 1,000 characters" }
        if kind == .allowance || ([IncomeStream.Kind.business, .rental].contains(kind) && monthly > economy.medianMonthlyIncomeMinor) {
            guard !rationale.isEmpty else { return "record a concise rationale explaining the recurring income and its source" }
        }
        guard playStyle == .simulation else { return nil }
        switch kind {
        case .wage:
            guard let tier = change.tier ?? current?.tier,
                  let band = economy.wageBands.first(where: { $0.name.caseInsensitiveCompare(tier) == .orderedSame })
            else { return "unknown or missing wage tier (no matching band)" }
            if monthly < band.minMonthlyMinor || monthly > band.maxMonthlyMinor {
                return "outside the \(band.name) band (\(Money.format(band.minMonthlyMinor, economy: economy)) to \(Money.format(band.maxMonthlyMinor, economy: economy)) per month)"
            }
        case .selfEmployment:
            let cap = rules.selfEmploymentMonthlyCap(economy: economy)
            if monthly > cap { return "over the self-employment cap of \(Money.format(cap, economy: economy)) per month; use business income for an established scalable business" }
        case .business, .allowance, .rental:
            break
        }
        return nil
    }

    private static func resolved(_ change: IncomeStreamChange, current: IncomeStream?, date: GameDate, personalAccountId: String = "personal") -> IncomeStream {
        let kind = change.kind ?? current?.kind ?? .wage
        var stream = IncomeStream(name: current?.name ?? change.name, kind: kind,
                                  tier: change.tier ?? current?.tier,
                                  monthlyMinor: change.monthlyMinor ?? current?.monthlyMinor ?? 0,
                                  startedOn: date)
        stream.accountId = change.accountId ?? current?.accountId ?? personalAccountId
        stream.pathId = change.pathId ?? (kind == .business ? current?.pathId : nil)
        return stream
    }

    private static func normalized(_ original: IncomeStreamChange) -> IncomeStreamChange {
        var change = original
        change.name = original.name.trimmingCharacters(in: .whitespacesAndNewlines)
        change.tier = original.tier?.trimmingCharacters(in: .whitespacesAndNewlines)
        change.accountId = original.accountId.map(key)
        change.pathId = original.pathId.map(key)
        change.effectiveFrom = original.effectiveFrom?.trimmingCharacters(in: .whitespacesAndNewlines)
        change.reason = original.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        return change
    }

    private static func isActive(_ stream: IncomeStream, on date: GameDate) -> Bool {
        stream.startedOn <= date && (stream.endedOn == nil || date < stream.endedOn!)
    }
    private static func key(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func priority(_ action: IncomeStreamChange.Action) -> Int {
        switch action { case .end: 0; case .change: 1; case .start: 2 }
    }
}
