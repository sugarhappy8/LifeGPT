import Foundation

public enum StoreError: Error, Equatable, Sendable {
    case notAStore
    case unsupportedSchema(found: Int)
    case alreadyExists
    case corrupt(String)
}

public enum Importance: String, Codable, Sendable { case major, minor }
public enum Origin: String, Codable, Sendable { case engine, narrator }

// MARK: Ledger

public struct NewLedgerEntry: Equatable, Sendable {
    public var date: GameDate
    public var sourceType: SourceType
    public var amountMinor: Int64
    public var reason: String
    public var counterparty: String?
    public var origin: Origin
    public var accountId: String

    public init(date: GameDate, sourceType: SourceType, amountMinor: Int64, reason: String,
                counterparty: String?, origin: Origin, accountId: String = "personal") {
        self.date = date
        self.sourceType = sourceType
        self.amountMinor = amountMinor
        self.reason = reason
        self.counterparty = counterparty
        self.origin = origin
        self.accountId = accountId
    }
}

public struct LedgerEntry: Equatable, Sendable {
    public var id: Int64
    public var date: GameDate
    public var sourceType: SourceType
    public var amountMinor: Int64
    public var reason: String
    public var counterparty: String?
    public var origin: Origin
    public var balanceAfterMinor: Int64
    public var accountId: String

    public init(id: Int64, date: GameDate, sourceType: SourceType, amountMinor: Int64, reason: String,
                counterparty: String?, origin: Origin, balanceAfterMinor: Int64, accountId: String = "personal") {
        self.id = id
        self.date = date
        self.sourceType = sourceType
        self.amountMinor = amountMinor
        self.reason = reason
        self.counterparty = counterparty
        self.origin = origin
        self.balanceAfterMinor = balanceAfterMinor
        self.accountId = accountId
    }
}

// MARK: Income

public struct IncomeStream: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case wage
        case selfEmployment = "self_employment"
        case business, allowance, rental
    }

    public var name: String
    public var kind: Kind
    public var tier: String?
    public var monthlyMinor: Int64
    public var startedOn: GameDate
    public var endedOn: GameDate?
    public var accountId: String
    public var pathId: String?

    public init(name: String, kind: Kind, tier: String?, monthlyMinor: Int64,
                startedOn: GameDate, endedOn: GameDate? = nil,
                accountId: String = "personal", pathId: String? = nil) {
        self.name = name
        self.kind = kind
        self.tier = tier
        self.monthlyMinor = monthlyMinor
        self.startedOn = startedOn
        self.endedOn = endedOn
        self.accountId = accountId
        self.pathId = pathId
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, tier, monthlyMinor, startedOn, endedOn, accountId, pathId
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(Kind.self, forKey: .kind)
        tier = try values.decodeIfPresent(String.self, forKey: .tier)
        monthlyMinor = try values.decode(Int64.self, forKey: .monthlyMinor)
        startedOn = try values.decode(GameDate.self, forKey: .startedOn)
        endedOn = try values.decodeIfPresent(GameDate.self, forKey: .endedOn)
        accountId = try values.decodeIfPresent(String.self, forKey: .accountId) ?? "personal"
        pathId = try values.decodeIfPresent(String.self, forKey: .pathId)
    }
}

public struct IncomeStreamChange: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case start, change, end }

    public var action: Action
    public var name: String
    public var kind: IncomeStream.Kind?
    public var tier: String?
    public var monthlyMinor: Int64?
    public var accountId: String?
    public var pathId: String?
    public var effectiveFrom: String?
    public var reason: String?

    public init(action: Action, name: String, kind: IncomeStream.Kind?, tier: String?, monthlyMinor: Int64?,
                accountId: String? = nil, pathId: String? = nil, effectiveFrom: String? = nil,
                reason: String? = nil) {
        self.action = action
        self.name = name
        self.kind = kind
        self.tier = tier
        self.monthlyMinor = monthlyMinor
        self.accountId = accountId
        self.pathId = pathId
        self.effectiveFrom = effectiveFrom
        self.reason = reason
    }
}

// MARK: Cast, decisions, state, events

public struct CastMember: Equatable, Sendable {
    public var name: String
    public var relation: String?
    public var notes: String?
    public var status: String
    public var firstMet: GameDate
    public var lastSeen: GameDate

    public init(name: String, relation: String?, notes: String?, status: String,
                firstMet: GameDate, lastSeen: GameDate) {
        self.name = name
        self.relation = relation
        self.notes = notes
        self.status = status
        self.firstMet = firstMet
        self.lastSeen = lastSeen
    }
}

public struct CastUpdate: Codable, Equatable, Sendable {
    public var name: String
    public var relation: String?
    public var notes: String?
    public var status: String?

    public init(name: String, relation: String?, notes: String?, status: String?) {
        self.name = name
        self.relation = relation
        self.notes = notes
        self.status = status
    }
}

public struct DecisionRecord: Codable, Equatable, Sendable {
    public var summary: String
    public var choice: String
    public var importance: Importance

    public init(summary: String, choice: String, importance: Importance) {
        self.summary = summary
        self.choice = choice
        self.importance = importance
    }
}

public struct DecisionRow: Equatable, Sendable {
    public var date: GameDate
    public var summary: String
    public var choice: String
    public var importance: Importance

    public init(date: GameDate, summary: String, choice: String, importance: Importance) {
        self.date = date
        self.summary = summary
        self.choice = choice
        self.importance = importance
    }
}

public struct LifeStateChange: Codable, Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct EventRecord: Codable, Equatable, Sendable {
    public var title: String
    public var importance: Importance
    public var uncanny: Bool

    public init(title: String, importance: Importance, uncanny: Bool) {
        self.title = title
        self.importance = importance
        self.uncanny = uncanny
    }
}

// MARK: Transcript and log

public struct ChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case player, narrator }

    public var id: Int64
    public var role: Role
    public var text: String
    public var date: GameDate

    public init(id: Int64, role: Role, text: String, date: GameDate) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

public struct TurnLog: Equatable, Sendable {
    public var fate: Int
    public var rejections: [String]
    public var repaired: Bool
    public var inputTokens: Int
    public var outputTokens: Int

    public init(fate: Int, rejections: [String], repaired: Bool, inputTokens: Int, outputTokens: Int) {
        self.fate = fate
        self.rejections = rejections
        self.repaired = repaired
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Everything one turn changes. `LifeStore.apply` writes all of it in one
/// transaction or none of it.
public struct AppliedTurn: Sendable {
    public var playerText: String
    public var narration: String
    public var newDate: GameDate
    public var ledger: [NewLedgerEntry]
    public var streamChanges: [IncomeStreamChange]
    public var decisions: [DecisionRecord]
    public var lifeState: [LifeStateChange]
    public var cast: [CastUpdate]
    public var events: [EventRecord]
    public var log: TurnLog
    public var expectedRevision: Int? = nil
    public var accountOpenings: [AccountOpening] = []
    public var authorNotes: String = ""
    public var choices: [String] = []
    public var paths: [OpportunityPath] = []
    public var threads: [StoryThread] = []
    public var positions: [FinancialPosition]? = nil
    public var ended: Bool = false
    public var businessState: BusinessSimulationState? = nil
    public var geography: LifeGeography? = nil
    public var relocatedEconomy: EconomyCard? = nil

    public init(playerText: String, narration: String, newDate: GameDate, ledger: [NewLedgerEntry],
                streamChanges: [IncomeStreamChange], decisions: [DecisionRecord],
                lifeState: [LifeStateChange], cast: [CastUpdate], events: [EventRecord], log: TurnLog) {
        self.playerText = playerText
        self.narration = narration
        self.newDate = newDate
        self.ledger = ledger
        self.streamChanges = streamChanges
        self.decisions = decisions
        self.lifeState = lifeState
        self.cast = cast
        self.events = events
        self.log = log
    }
}
