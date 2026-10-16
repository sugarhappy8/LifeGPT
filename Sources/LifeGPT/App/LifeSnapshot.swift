import Foundation
import LifeCore

struct LifeSnapshot {
    var character: LifeCharacter
    var economy: EconomyCard
    var balance: Int64
    var messages: [ChatMessage]
    var totalMessages: Int
    var ledger: [LedgerEntry]
    var streams: [IncomeStream]
    var cast: [CastMember]
    var decisions: [DecisionRow]
    var events: [TimelineEvent]
    var state: [String: String]
    var paths: [OpportunityPath]
    var threads: [StoryThread]
    var positions: [FinancialPosition]
    var chapters: [ChapterSummary]
    var world: [PlaceTimeBrief]
    var settings: SessionSettings
    var choices: [String]
    var logs: [TurnLog]
    var ended: Bool
    var accounts: [BankAccount]
    var revision: Int
    init(store: LifeStore, messageLimit: Int = 100) throws {
        character = try store.character(); economy = try store.economy(); balance = try store.balanceMinor()
        messages = try store.recentMessages(limit: messageLimit); totalMessages = try store.messageCount()
        ledger = try store.ledger(limit: 500); streams = try store.incomeStreams(); cast = try store.castMembers()
        decisions = try store.decisions(limit: 300); events = try store.events(limit: 300); state = try store.lifeState()
        paths = try store.paths(); threads = try store.threads(); positions = try store.positions()
        chapters = try store.chapters(); world = try store.placeTimeBriefs(); settings = try store.sessionSettings()
        choices = try store.choices(); logs = try store.turnLogs(); ended = try store.hasEnded()
        accounts = try store.accounts(); revision = try store.revision()
    }
    var worldNeedsReview: Bool {
        guard let brief = world.last else { return true }
        let placeChanged = state["residence"].map { $0.caseInsensitiveCompare(brief.location) != .orderedSame } ?? false
        return placeChanged || character.currentDate.year / 20 != brief.date.year / 20
    }
    var debt: Int64 { positions.filter(\.isDebt).reduce(0) { $0 + $1.principalMinor } }
    var assets: Int64 { positions.filter { !$0.isDebt }.reduce(0) { $0 + $1.principalMinor } }
    var netWorth: Int64 { balance + assets - debt }
    var household: HouseholdSupport { HouseholdSupport.resolve(settings: settings, state: state, background: character.background) }
    var personalLivingCost: Int64 { character.ageYears < 18 ? 0 : household.monthlyCost(economy: economy) }
    var monthlyIncome: Int64 { streams.filter { $0.endedOn == nil }.reduce(0) { $0 + $1.monthlyMinor } }
    var personalBalance: Int64 { accounts.first { $0.id == "personal" }?.balanceMinor ?? balance }
}
