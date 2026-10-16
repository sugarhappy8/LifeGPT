import Foundation

/// One money change the narrator proposes. The engine decides whether it stands.
public struct ProposedMoneyEntry: Codable, Equatable, Sendable {
    public var sourceType: SourceType
    public var amountMinor: Int64
    public var reason: String
    public var incomeStream: String?
    public var counterparty: String?
    public var fateUsed: Int?
    public var accountId: String?

    public init(sourceType: SourceType, amountMinor: Int64, reason: String,
                incomeStream: String? = nil, counterparty: String? = nil, fateUsed: Int? = nil, accountId: String? = nil) {
        self.sourceType = sourceType
        self.amountMinor = amountMinor
        self.reason = reason
        self.incomeStream = incomeStream
        self.counterparty = counterparty
        self.fateUsed = fateUsed
        self.accountId = accountId
    }
}

public struct TimeAdvance: Codable, Equatable, Sendable {
    public enum Unit: String, Codable, Sendable { case days, months, years }

    public var unit: Unit
    public var amount: Int

    public init(unit: Unit, amount: Int) {
        self.unit = unit
        self.amount = amount
    }
}

extension GameDate {
    public func adding(_ advance: TimeAdvance) -> GameDate {
        switch advance.unit {
        case .days: return adding(days: advance.amount)
        case .months: return adding(months: advance.amount)
        case .years: return adding(months: advance.amount * 12)
        }
    }
}

/// The state changes the narrator proposes for a turn. It is emitted before
/// the prose so the engine can validate it before the prose is shown.
public struct Resolution: Codable, Equatable, Sendable {
    public enum Zoom: String, Codable, Sendable { case scene, summary, montage }

    public var zoom: Zoom
    public var timeAdvance: TimeAdvance
    public var money: [ProposedMoneyEntry]
    public var incomeStreams: [IncomeStreamChange]
    public var decisions: [DecisionRecord]
    public var lifeStateChanges: [LifeStateChange]
    public var castUpdates: [CastUpdate]
    public var events: [EventRecord]
    public var pathUpdates: [PathUpdate]?
    public var threadUpdates: [StoryThread]?
    public var financialActions: [FinancialAction]?
    public var lifeEnded: Bool?
    public var crimeAttempt: CrimeAttempt?
    public var accountOpenings: [AccountOpening]?
    public var transfers: [AccountTransfer]?
    public var businessChanges: [BusinessChange]? = nil
    public var obligationChanges: [ObligationChange]? = nil
    public var accountChanges: [AccountLifecycleChange]? = nil
    public var saleProposals: [SaleProposal]? = nil
    public var residenceChanges: [ResidenceChange]? = nil

    public init(zoom: Zoom, timeAdvance: TimeAdvance, money: [ProposedMoneyEntry] = [],
                incomeStreams: [IncomeStreamChange] = [], decisions: [DecisionRecord] = [],
                lifeStateChanges: [LifeStateChange] = [], castUpdates: [CastUpdate] = [],
                events: [EventRecord] = [], pathUpdates: [PathUpdate]? = nil, threadUpdates: [StoryThread]? = nil,
                financialActions: [FinancialAction]? = nil, lifeEnded: Bool? = nil, crimeAttempt: CrimeAttempt? = nil,
                accountOpenings: [AccountOpening]? = nil, transfers: [AccountTransfer]? = nil) {
        self.zoom = zoom
        self.timeAdvance = timeAdvance
        self.money = money
        self.incomeStreams = incomeStreams
        self.decisions = decisions
        self.lifeStateChanges = lifeStateChanges
        self.castUpdates = castUpdates
        self.events = events
        self.pathUpdates = pathUpdates; self.threadUpdates = threadUpdates
        self.financialActions = financialActions; self.lifeEnded = lifeEnded; self.crimeAttempt = crimeAttempt
        self.accountOpenings = accountOpenings; self.transfers = transfers
    }
}

public struct TurnOutput: Codable, Equatable, Sendable {
    public var resolution: Resolution
    public var narration: String
    public var authorNotes: String?
    public var choices: [String]?

    public init(resolution: Resolution, narration: String, authorNotes: String? = nil, choices: [String]? = nil) {
        self.resolution = resolution
        self.narration = narration
        self.authorNotes = authorNotes
        self.choices = choices
    }
}

/// The contract's JSON uses snake_case keys.
public enum OutputCoding {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
