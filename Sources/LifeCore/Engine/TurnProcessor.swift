import Foundation

public struct TurnResult: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case narrated, outOfCharacter, ignored }

    public var kind: Kind
    public var text: String
    public var rejections: [String]
    public var repaired: Bool

    public init(kind: Kind, text: String, rejections: [String] = [], repaired: Bool = false) {
        self.kind = kind
        self.text = text
        self.rejections = rejections
        self.repaired = repaired
    }
}

public enum TurnError: Error, Equatable, Sendable {
    case narratorFailed(String)
    case refused
}

/// Runs one chat turn: classify the player's text, ask the narrator, validate
/// what it proposes, and write the result in a single transaction. The
/// player's words are an attempt; only validated proposals become facts.
public final class TurnProcessor {
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

    public func play(_ raw: String) async throws -> TurnResult {
        switch IntentGuard.classify(raw) {
        case .empty:
            return TurnResult(kind: .ignored, text: "")
        case .outOfCharacter(let question):
            return TurnResult(kind: .outOfCharacter, text: try OOCResponder.answer(question, store: store))
        case .attempt(let text):
            return try await playAttempt(text)
        }
    }

    // MARK: Attempt

    private func playAttempt(_ text: String) async throws -> TurnResult {
        let fateRoll = fate.roll()
        let truth = try GroundTruthBuilder.build(store: store, rules: rules)
        let request = NarratorRequest(groundTruth: truth, playerInput: text, fate: fateRoll,
                                      targetWords: truth.character.replyLengthWords,
                                      recentMessages: try store.recentMessages(limit: 6))
        var repairUsed = false
        var inputTokens = 0, outputTokens = 0

        // 1. Narrate; unusable output earns one repair.
        var result: NarratorResult
        do {
            result = try await narrator.narrate(request)
        } catch NarratorError.refused {
            throw TurnError.refused
        } catch let error as NarratorError {
            do {
                result = try await narrator.repair(
                    request, rejections: ["The previous output could not be used: \(Self.describe(error))"])
                repairUsed = true
            } catch NarratorError.refused {
                throw TurnError.refused
            } catch {
                throw TurnError.narratorFailed(String(describing: error))
            }
        }
        inputTokens += result.inputTokens
        outputTokens += result.outputTokens

        // 2. Validate; rejected changes earn one repair, unless one was already used.
        var evaluation = try evaluate(result.output, truth: truth, fate: fateRoll)
        var allRejections = evaluation.rejections
        if !evaluation.rejections.isEmpty && !repairUsed {
            repairUsed = true
            do {
                let second = try await narrator.repair(request, rejections: evaluation.rejections)
                inputTokens += second.inputTokens
                outputTokens += second.outputTokens
                let secondEvaluation = try evaluate(second.output, truth: truth, fate: fateRoll)
                allRejections += secondEvaluation.rejections
                result = second
                evaluation = secondEvaluation
            } catch NarratorError.refused {
                throw TurnError.refused
            } catch is NarratorError {
                // Repair failed: keep the first output and drop what was rejected.
            }
        }

        // 3. Apply what survived, all or nothing.
        var narration = result.output.narration
        if !evaluation.rejections.isEmpty {
            narration += "\n\n(Some changes were not applied: \(evaluation.rejections.joined(separator: "; ")).)"
        }
        let resolution = result.output.resolution
        let narratorEntries = evaluation.money.map {
            NewLedgerEntry(date: evaluation.newDate, sourceType: $0.sourceType, amountMinor: $0.amountMinor,
                           reason: $0.reason, counterparty: $0.counterparty, origin: .narrator)
        }
        let cast = resolution.castUpdates.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        try store.apply(AppliedTurn(
            playerText: text, narration: narration, newDate: evaluation.newDate,
            ledger: evaluation.payroll + narratorEntries, streamChanges: evaluation.streams,
            decisions: resolution.decisions, lifeState: resolution.lifeStateChanges, cast: cast,
            events: resolution.events,
            log: TurnLog(fate: fateRoll, rejections: allRejections, repaired: repairUsed,
                         inputTokens: inputTokens, outputTokens: outputTokens)))
        return TurnResult(kind: .narrated, text: narration, rejections: evaluation.rejections, repaired: repairUsed)
    }

    // MARK: Validation

    private struct Evaluation {
        var rejections: [String] = []
        var newDate: GameDate
        var payroll: [NewLedgerEntry] = []
        var money: [ProposedMoneyEntry] = []
        var streams: [IncomeStreamChange] = []
    }

    /// Checks a narrator output without writing anything. Rejected pieces are
    /// described in `rejections` and left out of the accepted lists.
    private func evaluate(_ output: TurnOutput, truth: GroundTruth, fate: Int) throws -> Evaluation {
        let resolution = output.resolution
        let start = truth.character.currentDate
        var evaluation = Evaluation(newDate: start)
        var days = 0

        if let problem = Self.timeProblem(resolution.timeAdvance) {
            evaluation.rejections.append("time_advance: \(problem)")
        } else {
            evaluation.newDate = start.adding(resolution.timeAdvance)
            days = evaluation.newDate.daysSince(start)
        }

        evaluation.payroll = TimeEngine.plan(days: days, character: truth.character,
                                             streams: truth.incomeStreams, economy: truth.economy)
        let projectedBalance = evaluation.payroll.reduce(truth.balanceMinor) { $0 + $1.amountMinor }

        let streamVerdicts = MoneyValidator.validate(resolution.incomeStreams, existing: truth.incomeStreams,
                                                     economy: truth.economy, rules: rules)
        for (change, verdict) in zip(resolution.incomeStreams, streamVerdicts) {
            switch verdict {
            case .accepted: evaluation.streams.append(change)
            case .rejected(let reason):
                evaluation.rejections.append("income_streams \(change.action.rawValue) \"\(change.name)\": \(reason)")
            }
        }

        var giftGaps: [String: Int] = [:]
        for entry in resolution.money where entry.sourceType == .gift || entry.sourceType == .inheritance {
            if let giver = entry.counterparty, let last = try store.lastGiftDate(from: giver) {
                giftGaps[giver] = evaluation.newDate.daysSince(last)
            }
        }
        let lastWindfall = try store.lastLedgerDate(source: .windfall).map { evaluation.newDate.daysSince($0) }
        let context = MoneyContext(economy: truth.economy, familyTier: truth.character.familyWealthTier,
                                   balanceMinor: projectedBalance, elapsedDays: days, fate: fate,
                                   castNames: Set(truth.cast.map(\.name)), daysSinceLastWindfall: lastWindfall,
                                   daysSinceLastGiftByGiver: giftGaps, rules: rules)
        let moneyVerdicts = MoneyValidator.validate(resolution.money, in: context)
        for (entry, verdict) in zip(resolution.money, moneyVerdicts) {
            switch verdict {
            case .accepted: evaluation.money.append(entry)
            case .rejected(let reason):
                evaluation.rejections.append("money \(entry.sourceType.rawValue) \(entry.amountMinor): \(reason)")
            }
        }
        return evaluation
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
