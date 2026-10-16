import Foundation

public struct TurnResult: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case narrated, outOfCharacter, ignored }

    public var kind: Kind
    public var text: String
    public var rejections: [String]
    public var repaired: Bool
    public var contextNotice: String = ""

    public init(kind: Kind, text: String, rejections: [String] = [], repaired: Bool = false) {
        self.kind = kind
        self.text = text
        self.rejections = rejections
        self.repaired = repaired
    }
}

public enum TurnError: Error, Equatable, Sendable {
    case narratorFailed(String)
    case validationFailed(reasons: [String])
    case refused
}

/// Runs one chat turn: classify the player's text, ask the narrator, validate
/// what it proposes, and write the result in a single transaction. The
/// player's words are an attempt; only validated proposals become facts.
public actor TurnProcessor {
    private var busy = false
    private let store: LifeStore
    private let narrator: any Narrator
    private var fate: any FateSource
    private let rules: MoneyRules

    public init(store: LifeStore, narrator: any Narrator, fate: any FateSource, rules: MoneyRules = .v1) {
        self.store = store
        self.narrator = narrator
        self.fate = fate
        self.rules = rules
    }

    public func play(_ raw: String, targetWords: Int? = nil, skipTime: TimeAdvance? = nil) async throws -> TurnResult {
        guard !busy else { throw ValidationError.invalid("A turn is already in progress.") }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        guard raw.count <= 12_000 else { throw ValidationError.invalid("Keep a single action under 12,000 characters.") }
        switch IntentGuard.classify(raw) {
        case .empty:
            return TurnResult(kind: .ignored, text: "")
        case .outOfCharacter(let question):
            return TurnResult(kind: .outOfCharacter, text: try OOCResponder.answer(question, store: store))
        case .attempt(let text):
            guard try !store.hasEnded() else { throw ValidationError.invalid("This life has ended. You can read its story or begin a new life.") }
            try ContentGuard.check(text, characterAge: store.character().ageYears)
            return try await playAttempt(text, targetWords: targetWords, skipTime: skipTime)
        }
    }

    // MARK: Attempt

    private func playAttempt(_ text: String, targetWords: Int?, skipTime: TimeAdvance?) async throws -> TurnResult {
        if let skipTime, let problem = Self.timeProblem(skipTime) { throw ValidationError.invalid(problem) }
        let revision = try store.revision()
        let fateRoll = fate.roll()
        let truth = try GroundTruthBuilder.build(store: store, rules: rules)
        let memory = try ContextBuilder.memory(store: store, input: text)
        let adjustedFate = GameDifficulty.effectiveFate(fateRoll, difficulty: memory.settings.difficulty)
        var request = NarratorRequest(groundTruth: truth, playerInput: text, fate: adjustedFate,
                                      targetWords: min(2000, max(60, targetWords ?? truth.character.replyLengthWords)),
                                      recentMessages: try store.recentMessages(limit: 12))
        request.memory = memory
        request.rawFate = fateRoll
        request.requestedTime = skipTime
        var repairUsed = false
        var allRejections: [String] = []
        var inputTokens = 0, outputTokens = 0

        // 1. Narrate; unusable output earns one repair.
        var result: NarratorResult
        do {
            result = try await narrator.narrate(request)
        } catch NarratorError.refused {
            throw TurnError.refused
        } catch let error as NarratorError {
            allRejections.append("narrator output: \(Self.describe(error))")
            do {
                result = try await narrator.repair(
                    request, rejections: ["The previous output could not be used: \(Self.describe(error))"])
                repairUsed = true
            } catch NarratorError.refused {
                throw TurnError.refused
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw TurnError.validationFailed(reasons: allRejections + ["Repair failed: \(String(error.localizedDescription.prefix(200)))"])
            }
        }
        result.output = Self.normalized(result.output)
        inputTokens += result.inputTokens
        outputTokens += result.outputTokens

        // 2. Validate; rejected changes earn one repair, unless one was already used.
        var evaluation = try evaluate(result.output, truth: truth, fate: adjustedFate, skipTime: skipTime)
        allRejections += evaluation.rejections
        if !evaluation.rejections.isEmpty && !repairUsed {
            repairUsed = true
            var second: NarratorResult?
            do {
                second = try await narrator.repair(request, rejections: evaluation.rejections)
            } catch NarratorError.refused {
                throw TurnError.refused
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The first reply is invalid. A failed repair cannot make any of its changes safe to commit.
                throw TurnError.validationFailed(reasons: evaluation.rejections + ["Repair failed: \(String(error.localizedDescription.prefix(200)))"])
            }
            if var repaired = second {
                repaired.output = Self.normalized(repaired.output)
                inputTokens += repaired.inputTokens
                outputTokens += repaired.outputTokens
                let repairedEvaluation = try evaluate(repaired.output, truth: truth, fate: adjustedFate, skipTime: skipTime)
                allRejections += repairedEvaluation.rejections
                result = repaired
                evaluation = repairedEvaluation
            }
        }

        // 3. Only a fully validated turn can become story or durable state.
        guard evaluation.rejections.isEmpty else { throw TurnError.validationFailed(reasons: evaluation.rejections) }
        let narration = result.output.narration
        let resolution = result.output.resolution
        // Store the latest audit with the turn using existing state storage; old saves need no migration.
        evaluation.engineState += [
            LifeStateChange(key: "_engine_last_difficulty", value: String(memory.settings.difficulty)),
            LifeStateChange(key: "_engine_last_effective_fate", value: String(adjustedFate))
        ]
        try Task.checkCancellation()
        try ContentGuard.check(narration, characterAge: truth.character.ageYears)
        var turn = AppliedTurn(
            playerText: text, narration: narration, newDate: evaluation.newDate,
            ledger: evaluation.payroll, streamChanges: evaluation.streams,
            decisions: Array(resolution.decisions.prefix(20)),
            lifeState: evaluation.state + evaluation.engineState,
            cast: evaluation.cast,
            events: resolution.events + evaluation.engineEvents,
            log: TurnLog(fate: fateRoll, rejections: allRejections, repaired: repairUsed,
                         inputTokens: inputTokens, outputTokens: outputTokens))
        turn.businessState = evaluation.businessState
        turn.geography = (result.output.resolution.residenceChanges ?? []).isEmpty ? nil : evaluation.geography
        turn.relocatedEconomy = evaluation.relocatedEconomy
        turn.expectedRevision = revision
        turn.accountOpenings = evaluation.accountOpenings
        turn.authorNotes = result.output.authorNotes ?? ""
        turn.choices = Array((result.output.choices ?? []).prefix(4)).map { String($0.prefix(300)) }
        turn.paths = evaluation.paths; turn.threads = evaluation.threads; turn.positions = evaluation.positions
        turn.ended = resolution.lifeEnded ?? false
        try store.apply(turn)
        // Compaction is an optional context optimization; the committed turn must remain successful if it fails.
        try? MemoryCompactor.compactIfNeeded(store: store)
        var resultValue = TurnResult(kind: .narrated, text: narration, rejections: evaluation.rejections, repaired: repairUsed)
        resultValue.contextNotice = result.contextNotice
        return resultValue
    }

    // MARK: Validation

    private struct Evaluation {
        var rejections: [String] = []
        var newDate: GameDate
        var payroll: [NewLedgerEntry] = []
        var money: [ProposedMoneyEntry] = []
        var streams: [IncomeStreamChange] = []
        var positions: [FinancialPosition] = []
        var paths: [OpportunityPath] = []
        var cast: [CastUpdate] = []
        var state: [LifeStateChange] = []
        var threads: [StoryThread] = []
        var engineState: [LifeStateChange] = []
        var engineEvents: [EventRecord] = []
        var accountOpenings: [AccountOpening] = []
        var businessState: BusinessSimulationState? = nil
        var geography: LifeGeography? = nil
        var relocatedEconomy: EconomyCard? = nil
    }

    /// Checks a narrator output without writing anything. Rejected pieces are
    /// described in `rejections` and left out of the accepted lists.
    private func evaluate(_ output: TurnOutput, truth: GroundTruth, fate: Int, skipTime: TimeAdvance?) throws -> Evaluation {
        var resolution = output.resolution
        resolution.castUpdates = resolution.castUpdates.map { original in
            var update = original
            if let person = CastIdentity.resolve(update.name, in: truth.cast) { update.name = person.name }
            return update
        }
        let start = truth.character.currentDate
        var evaluation = Evaluation(newDate: start)
        var days = 0

        let advance = skipTime ?? resolution.timeAdvance
        if let skipTime, resolution.timeAdvance != skipTime { evaluation.rejections.append("time_advance must match the player-selected skip duration") }
        if let problem = Self.timeProblem(advance) {
            evaluation.rejections.append("time_advance: \(problem)")
        } else {
            let candidate = start.adding(advance)
            if candidate.year > 9999 {
                evaluation.rejections.append("time_advance exceeds the supported calendar range")
            } else {
                evaluation.newDate = candidate
                days = evaluation.newDate.daysSince(start)
            }
        }

        let oldPaths = try store.paths()
        let opened = BankingEngine.open(resolution.accountOpenings ?? [], existing: truth.accounts)
        evaluation.accountOpenings = opened.openings
        evaluation.rejections += opened.rejections
        let geography = try store.geography()
        do { evaluation.geography = try geography.applying(resolution.residenceChanges ?? [], from: start, through: evaluation.newDate) }
        catch { evaluation.rejections.append(error.localizedDescription) }
        do {
            try store.validateAccountClosures(resolution.accountChanges ?? [], incomeChanges: resolution.incomeStreams)
            try store.validateSaleRetentions(resolution.saleProposals ?? [])
        }
        catch { evaluation.rejections.append(error.localizedDescription) }
        let prepared = try BusinessEngine.prepare(state: store.businessSimulation(), accounts: opened.accounts,
            start: start, end: evaluation.newDate, economy: truth.economy,
            businessChanges: resolution.businessChanges ?? [], obligationChanges: resolution.obligationChanges ?? [],
            accountChanges: resolution.accountChanges ?? [], saleProposals: resolution.saleProposals ?? [], revision: store.revision() + 1)
        evaluation.rejections += prepared.rejections
        let newPaths = (resolution.pathUpdates ?? []).filter { update in !oldPaths.contains { $0.id == update.id } }
            .map { OpportunityPath(id: $0.id, title: $0.title, stage: $0.stage, startedOn: evaluation.newDate) }
        let income = IncomeEngine.plan(changes: resolution.incomeStreams, existing: truth.incomeStreams,
            start: start, end: evaluation.newDate, economy: truth.economy, playStyle: truth.playStyle,
            accounts: prepared.accounts, paths: oldPaths + newPaths, rules: rules, personalAccountId: prepared.state.defaultPersonalAccountId)
        evaluation.streams = income.changes
        evaluation.rejections += income.rejections
        for change in income.changes where change.action != .end {
            let date = change.effectiveFrom.flatMap(GameDate.init(iso:)) ?? evaluation.newDate
            if truth.playStyle == .simulation, date.ageYears(bornOn: truth.character.birthDate) < 13,
               change.kind == .wage || change.kind == .selfEmployment {
                evaluation.rejections.append("income_streams: young children cannot hold jobs")
            }
        }
        // Creating a managed business is an explicit accounting conversion, never
        // an implicit second deposit over an existing net-income stream.
        let managed = Set(prepared.state.businesses.map(\.accountId))
        for stream in income.streams where managed.contains(stream.accountId) && (stream.endedOn == nil || stream.endedOn! > evaluation.newDate) {
            evaluation.rejections.append("End legacy income '\(stream.name)' when converting its account to managed gross business accounting.")
        }
        let settled = try SimulationSettlement.run(prepared: prepared, character: truth.character, end: evaluation.newDate,
            streams: income.streams, economy: truth.economy, positions: store.positions(), paths: oldPaths, household: truth.household, geography: evaluation.geography, originalResidence: truth.currentJurisdiction)
        evaluation.businessState = settled.business
        evaluation.relocatedEconomy = settled.economy != truth.economy ? settled.economy : nil
        evaluation.accountOpenings += settled.openings
        var finances = settled.finances
        let crime = CrimeEngine.resolve(resolution.crimeAttempt, age: truth.character.ageYears, date: evaluation.newDate,
            fate: fate, economy: truth.economy, lastAttempt: truth.lifeState["_engine_last_crime_date"].flatMap(GameDate.init(iso:)))
        finances = try FinanceEngine.applyCrime(crime, date: evaluation.newDate, to: finances)
        evaluation.engineState = crime.state
        evaluation.engineEvents = crime.event.map { [$0] } ?? []
        let projectedBalance = finances.balance
        let continuity = ContinuityValidator.validate(resolution, truth: truth)
        evaluation.cast = continuity.cast; evaluation.state = continuity.state; evaluation.threads = continuity.threads
        evaluation.rejections += continuity.rejections

        let money = resolution.money.map { original in
            var entry = original
            if [.gift, .inheritance].contains(entry.sourceType), let name = entry.counterparty,
               let person = CastIdentity.resolve(name, in: truth.cast) { entry.counterparty = person.name }
            return entry
        }
        var giftGaps: [String: Int] = [:]
        for entry in money where entry.sourceType == .gift || entry.sourceType == .inheritance {
            if let giver = entry.counterparty, let last = try store.lastGiftDate(from: giver) {
                giftGaps[giver] = evaluation.newDate.daysSince(last)
            }
        }
        let lastWindfall = try store.lastLedgerDate(source: .windfall).map { evaluation.newDate.daysSince($0) }
        let lastGifts = [try store.lastLedgerDate(source: .gift), try store.lastLedgerDate(source: .inheritance)]
        let daysSinceAnyGift = lastGifts.compactMap { $0 }.max().map { evaluation.newDate.daysSince($0) }
        var context = MoneyContext(economy: truth.economy, familyTier: truth.character.familyWealthTier,
                                   balanceMinor: projectedBalance, elapsedDays: days, fate: fate,
                                   castNames: Set(truth.cast.map(\.name)), daysSinceLastWindfall: lastWindfall,
                                   daysSinceLastGiftByGiver: giftGaps, daysSinceLastAnyGift: daysSinceAnyGift,
                                   rules: rules)
        context.playStyle = truth.playStyle
        context.personalAccountId = finances.personalAccountId
        context.accountBalances = finances.accountBalances
        let familyWords = ["mother", "father", "parent", "sister", "brother", "sibling", "uncle", "aunt", "grandparent", "grandmother", "grandfather", "cousin", "relative", "family", "spouse"]
        for person in truth.cast {
            let relation = person.relation?.lowercased() ?? ""
            context.giverTiers[person.name] = familyWords.contains(where: relation.contains) ? truth.character.familyWealthTier : .middle
            context.giverStatuses[person.name] = person.status.lowercased()
            // A validated death in this turn must also govern gifts and inheritances in this turn.
            if let update = evaluation.cast.last(where: { $0.name.caseInsensitiveCompare(person.name) == .orderedSame }),
               let status = update.status { context.giverStatuses[person.name] = status }
        }
        context.recentSideHustleMinor = try store.sideHustleTotal(since: evaluation.newDate.adding(days: -6))
        // Credit valid receipts before moving funds, then validate spending against
        // those destination balances. Transfers can fund an ordinary purchase.
        for phase in 0...1 {
            let entries = money.filter { phase == 0 ? $0.amountMinor >= 0 : $0.amountMinor < 0 }
            context.accountBalances = finances.accountBalances
            let verdicts = MoneyValidator.validate(entries, in: context)
            var accepted: [NewLedgerEntry] = []
            for (entry, verdict) in zip(entries, verdicts) {
                switch verdict {
                case .accepted:
                    evaluation.money.append(entry)
                    accepted.append(NewLedgerEntry(date: evaluation.newDate, sourceType: entry.sourceType,
                        amountMinor: entry.amountMinor, reason: entry.reason, counterparty: entry.counterparty,
                        origin: .narrator, accountId: entry.accountId ?? finances.personalAccountId))
                case .rejected(let reason):
                    evaluation.rejections.append("money \(entry.sourceType.rawValue) \(entry.amountMinor): \(reason)")
                }
            }
            finances = try FinanceEngine.record(accepted, to: finances)
            if phase == 0 {
                finances = try BankingEngine.transfer(resolution.transfers ?? [], date: evaluation.newDate, plan: finances)
            }
        }
        let ageAtEnd = evaluation.newDate.ageYears(bornOn: truth.character.birthDate)
        let pathPlan = PathEngine.plan(resolution.pathUpdates ?? [], existing: oldPaths, date: evaluation.newDate,
            age: ageAtEnd, economy: truth.economy, balance: finances.balance, fate: fate, playStyle: truth.playStyle,
            personalAccountId: finances.personalAccountId)
        finances = try FinanceEngine.record(pathPlan.ledger, to: finances)
        finances = try FinanceEngine.actions(resolution.financialActions ?? [], date: evaluation.newDate,
            age: ageAtEnd, economy: truth.economy, streams: income.streams, plan: finances, household: truth.household)
        evaluation.payroll = finances.ledger; evaluation.positions = finances.positions; evaluation.paths = pathPlan.paths
        evaluation.rejections += pathPlan.rejections + finances.rejections
        return evaluation
    }

    /// Trims the names the narrator invents, so padding or stray spaces cannot
    /// create a second "person" or a second giver.
    private static func normalized(_ output: TurnOutput) -> TurnOutput {
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var out = output
        out.resolution.castUpdates = out.resolution.castUpdates.map { var u = $0; u.name = trimmed(u.name); return u }
        out.resolution.money = out.resolution.money.map { var m = $0; m.counterparty = m.counterparty.map(trimmed); return m }
        out.resolution.incomeStreams = out.resolution.incomeStreams.map { var c = $0; c.name = trimmed(c.name); return c }
        return out
    }

    /// At most 20 years may pass in one turn.
    private static func timeProblem(_ advance: TimeAdvance) -> String? {
        if advance.amount < 0 { return "must not be negative" }
        let limit: Int
        switch advance.unit {
        case .days: limit = 7_300
        case .months: limit = 240
        case .years: limit = 20
        }
        if advance.amount > limit {
            return "\(advance.amount) \(advance.unit.rawValue) exceeds the limit of 20 years per turn"
        }
        return nil
    }

    private static func describe(_ error: NarratorError) -> String {
        switch error {
        case .refused: return "the request was refused"
        case .truncated: return "the reply was cut off before the JSON finished"
        case .malformedOutput(let detail): return "malformed output (\(detail))"
        }
    }
}
