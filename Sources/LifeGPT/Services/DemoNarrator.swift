import Foundation
import LifeCore

/// A clearly labeled offline walkthrough; real open-ended narration requires a configured model.
struct DemoNarrator: Narrator {
    func narrate(_ request: NarratorRequest) async throws -> NarratorResult { make(request) }
    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult {
        NarratorResult(output: TurnOutput(resolution: Resolution(zoom: .scene, timeAdvance: request.requestedTime ?? TimeAdvance(unit: .days, amount: 1)),
            narration: "The plan needs more time. You take a smaller step, leaving the grand promises for another day.",
            choices: ["I walk around the neighborhood.", "I ask someone about work."]), inputTokens: 0, outputTokens: 0)
    }
    private func make(_ r: NarratorRequest) -> NarratorResult {
        let input = r.playerInput.lowercased(), c = r.groundTruth.character
        var resolution = Resolution(zoom: .scene, timeAdvance: r.requestedTime ?? TimeAdvance(unit: .days, amount: 1))
        var prose: String
        if r.requestedTime != nil {
            resolution.zoom = .summary
            prose = "Days collect in familiar places: the route home, the same window lit at dusk, the sound of someone setting a cup down in the next room. A few things become easier through repetition. Others wait.\n\nWhen you stop to take stock, time has moved on. The ledger records what came in, what went out, and what still needs attention."
        } else if input.contains("job") || input.contains("work") {
            if c.ageYears >= 16, !r.groundTruth.incomeStreams.contains(where: { $0.endedOn == nil && $0.kind == .wage }), let band = r.groundTruth.economy.wageBands.first {
                resolution.incomeStreams = [IncomeStreamChange(action: .start, name: "Neighborhood shop", kind: .wage, tier: band.name, monthlyMinor: band.minMonthlyMinor)]
                resolution.lifeStateChanges = [LifeStateChange(key: "career", value: "Shop assistant")]
                resolution.decisions = [DecisionRecord(summary: "Accepted a first shift", choice: "Work at the neighborhood shop", importance: .major)]
                prose = "The shopkeeper pushes a battered notebook across the counter. Your name goes beneath two others. \"Tomorrow, then. Early.\"\n\nThere is no ceremony to it. Outside, the street is unchanged, but you find yourself measuring the walk home in minutes. Tomorrow those minutes will matter."
            } else { prose = "You ask around. Work has a rhythm here, and learning it takes more than an afternoon. Someone suggests a name, then a street. You carry both home with you." }
        } else if input.contains("business") {
            resolution.pathUpdates = [PathUpdate(id: "small-business", title: "A small neighborhood business", stage: .idea, notes: "Find a need, save capital, and test a modest first offer.")]
            prose = "You turn the idea over until it has edges: one customer, one useful thing, one price someone might actually pay. The larger dream can wait.\n\nOn a scrap of paper you write the first question: what do people here need?"
        } else if input.contains("family") || input.contains("friend") {
            resolution.castUpdates = [CastUpdate(name: "Sam", relation: "neighbor", notes: "Keeps an extra chair by the window; listens before speaking.", status: "alive")]
            prose = "Sam has moved the spare chair into the patch of afternoon sun. You sit without being asked. For a while neither of you says much.\n\nThen comes a small question about your day, and you discover you have more to say than you expected."
        } else if input.contains("sell") && !input.contains("million") && !input.contains("billion") {
            let amount = max(1, min(1200, r.groundTruth.economy.medianMonthlyIncomeMinor / 100))
            resolution.money = [ProposedMoneyEntry(sourceType: .sideHustle, amountMinor: amount, reason: "A small sale at the neighborhood market")]
            prose = "The first person only looks. The second asks your price and walks away. The third returns after a few minutes, counting out a modest payment.\n\nIt is a beginning small enough to fit in your pocket."
        } else {
            let scenes = [
                "The street is quieter than you expected. Behind an open window, someone is practicing the same few notes, stopping at the same place each time. You slow your steps. By the time you reach the corner, they have finally played it through.",
                "You leave with no particular destination. The day offers small things: a familiar face, a closed shop, a conversation you almost join. At the next turning you pause, aware that choosing a direction is still a choice.",
                "For once, nothing urgent arrives. You have an hour to yourself, and the strange responsibility of deciding what to do with it. The light moves across the room while you think."
            ]
            prose = scenes[(r.fate - 1) % scenes.count]
        }
        if resolution.timeAdvance.amount > 30 { resolution.zoom = .montage }
        return NarratorResult(output: TurnOutput(resolution: resolution, narration: prose,
            authorNotes: "Keep ordinary routines and established relationships in view.",
            choices: ["I look for work nearby.", "I spend time with a friend.", "I explore the neighborhood."]), inputTokens: 0, outputTokens: 0)
    }
}
