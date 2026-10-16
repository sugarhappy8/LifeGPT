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
    var business: BusinessSimulationState
    var geography: LifeGeography
    init(store: LifeStore, messageLimit: Int = 100) throws {
        character = try store.character(); economy = try store.economy(); balance = try store.balanceMinor()
        messages = try store.recentMessages(limit: messageLimit); totalMessages = try store.messageCount()
        ledger = try store.ledger(limit: 500); streams = try store.incomeStreams(); cast = try store.castMembers()
        decisions = try store.decisions(limit: 300); events = try store.events(limit: 300); state = try store.lifeState()
        paths = try store.paths(); threads = try store.threads(); positions = try store.positions()
        chapters = try store.chapters(); world = try store.placeTimeBriefs(); settings = try store.sessionSettings()
        choices = try store.choices(); logs = try store.turnLogs(); ended = try store.hasEnded()
        accounts = try store.accounts(); revision = try store.revision()
        business = try store.businessSimulation(); geography = try store.geography()
    }
    var worldNeedsReview: Bool {
        guard let brief = world.last else { return true }
        let placeChanged = state["residence"].map { $0.caseInsensitiveCompare(brief.location) != .orderedSame } ?? false
        return placeChanged || character.currentDate.year / 20 != brief.date.year / 20
    }
    var accessibleAccounts: [BankAccount] { accounts.filter(\.isAccessible) }
    var currentResidence: JurisdictionRef? { geography.residence(on: character.currentDate) }
    var ownedPositions: [FinancialPosition] { positions.filter { position in accessibleAccounts.contains { $0.id == (position.accountId ?? "personal") } } }
    var ownedBusinessIDs: Set<String> { Set(business.businesses.filter { $0.status != .sold }.map(\.id)) }
    var unpaidObligations: Int64 { business.payables.filter { ownedBusinessIDs.contains($0.businessId) }.reduce(0) { $0 + $1.remainingMinor } }
    var debt: Int64 { ownedPositions.filter(\.isDebt).reduce(0) { $0 + $1.principalMinor } + unpaidObligations }
    var assets: Int64 { ownedPositions.filter { !$0.isDebt }.reduce(0) { $0 + $1.principalMinor } }
    var internalReceivables: Int64 {
        business.payables.filter { payable in
            ownedBusinessIDs.contains(payable.businessId) && payable.kind != .tax &&
            accessibleAccounts.contains { $0.id == payable.toAccountId }
        }.reduce(0) { sum, payable in
            sum + max(0, payable.remainingMinor - max(0, payable.withholdingMinor - payable.reservedMinor))
        }
    }
    var netWorth: Int64 { balance + reservedTaxes + assets + internalReceivables - debt }
    var household: HouseholdSupport { HouseholdSupport.resolve(settings: settings, state: state, background: character.background) }
    var personalLivingCost: Int64 { character.ageYears < 18 ? 0 : household.monthlyCost(economy: economy) }
    var monthlyIncome: Int64 { streams.filter { stream in stream.endedOn == nil && accessibleAccounts.contains(where: { $0.id == stream.accountId }) }.reduce(0) { $0 + $1.monthlyMinor } }
    var personalBalance: Int64 { accounts.first { $0.id == business.defaultPersonalAccountId && $0.isAccessible }?.balanceMinor ?? 0 }
    var businessCash: Int64 { accessibleAccounts.filter { $0.businessId != nil }.reduce(0) { $0 + $1.balanceMinor } }
    var reservedTaxes: Int64 { accounts.filter { $0.status == .active && $0.kind == .taxReserve }.reduce(0) { $0 + $1.balanceMinor } }
    var currentObligations: [RecurringObligation] { business.obligations.filter { $0.effectiveFrom <= character.currentDate && ($0.endedOn == nil || $0.endedOn! > character.currentDate) } }
    func monthlyTotal(_ kind: RecurringObligation.Kind) -> Int64 { currentObligations.filter { $0.kind == kind }.reduce(0) { $0 + $1.monthlyMinor * Int64($1.headcount) } }
}
