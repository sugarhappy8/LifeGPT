import Foundation
@testable import LifeCore

/// A narrator that replays queued results and records what it was asked.
final class ScriptedNarrator: Narrator, @unchecked Sendable {
    enum Step {
        case output(TurnOutput)
        case failure(NarratorError)
        /// Any other error, such as a network failure.
        case error(any Error)
    }

    var narrateSteps: [Step]
    var repairSteps: [Step]
    private(set) var narrateCalls = 0
    private(set) var repairCalls = 0
    private(set) var rejectionsGiven: [[String]] = []
    private(set) var lastRequest: NarratorRequest?

    init(narrate: [Step], repair: [Step] = []) {
        narrateSteps = narrate
        repairSteps = repair
    }

    func narrate(_ request: NarratorRequest) async throws -> NarratorResult {
        narrateCalls += 1
        lastRequest = request
        return try next(&narrateSteps)
    }

    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult {
        repairCalls += 1
        rejectionsGiven.append(rejections)
        lastRequest = request
        return try next(&repairSteps)
    }

    private func next(_ steps: inout [Step]) throws -> NarratorResult {
        guard !steps.isEmpty else { throw NarratorError.malformedOutput("script exhausted") }
        switch steps.removeFirst() {
        case .output(let out): return NarratorResult(output: out, inputTokens: 100, outputTokens: 50)
        case .failure(let error): throw error
        case .error(let error): throw error
        }
    }
}

/// Builds a `TurnOutput` with sensible defaults (no time passing, no changes).
func output(_ narration: String = "You act.", time: TimeAdvance = TimeAdvance(unit: .days, amount: 0),
            money: [ProposedMoneyEntry] = [], streams: [IncomeStreamChange] = [],
            decisions: [DecisionRecord] = [], lifeState: [LifeStateChange] = [],
            cast: [CastUpdate] = [], events: [EventRecord] = []) -> TurnOutput {
    TurnOutput(resolution: Resolution(zoom: .scene, timeAdvance: time, money: money, incomeStreams: streams,
                                      decisions: decisions, lifeStateChanges: lifeState,
                                      castUpdates: cast, events: events),
               narration: narration)
}
