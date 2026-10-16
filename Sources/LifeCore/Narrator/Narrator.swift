import Foundation

/// The binding facts the narrator is given every turn. Anything here wins over
/// anything the narrator remembers or the player claims.
public struct GroundTruth: Equatable, Sendable {
    public var character: Character
    public var economy: EconomyCard
    public var balanceMinor: Int64
    public var incomeStreams: [IncomeStream]
    public var recentLedger: [LedgerEntry]
    public var cast: [CastMember]
    public var recentDecisions: [DecisionRow]
    public var lifeState: [String: String]
    public var guardrails: Guardrails
    public var household: HouseholdSupport = .independent
    public var accounts: [BankAccount] = []
    public var playStyle: PlayStyle = .simulation
    public var simulationContext: String = ""
    public var currentJurisdiction: JurisdictionRef? = nil

    public init(character: Character, economy: EconomyCard, balanceMinor: Int64, incomeStreams: [IncomeStream],
                recentLedger: [LedgerEntry], cast: [CastMember], recentDecisions: [DecisionRow],
                lifeState: [String: String], guardrails: Guardrails) {
        self.character = character
        self.economy = economy
        self.balanceMinor = balanceMinor
        self.incomeStreams = incomeStreams
        self.recentLedger = recentLedger
        self.cast = cast
        self.recentDecisions = recentDecisions
        self.lifeState = lifeState
        self.guardrails = guardrails
    }
}

public enum GroundTruthBuilder {
    /// Everything about the chat, unscored: all cast, the last 10 ledger rows and
    /// decisions. Guardrails are computed for a 30-day window ("per 30 days").
    public static func build(store: LifeStore, rules: MoneyRules) throws -> GroundTruth {
        let character = try store.character()
        let economy = try store.economy()
        var truth = GroundTruth(
            character: character, economy: economy, balanceMinor: try store.balanceMinor(),
            incomeStreams: try store.incomeStreams(), recentLedger: try store.ledger(limit: 10),
            cast: try store.castMembers(), recentDecisions: try store.decisions(limit: 10),
            lifeState: try store.lifeState(),
            guardrails: rules.guardrails(economy: economy, familyTier: character.familyWealthTier, elapsedDays: 30))
        truth.household = HouseholdSupport.resolve(settings: try store.sessionSettings(), state: truth.lifeState, background: character.background)
        truth.accounts = try store.accounts()
        truth.playStyle = try store.sessionSettings().playStyle
        let geography = try store.geography()
        truth.currentJurisdiction = geography.residence(on: character.currentDate)
        if let jurisdiction = truth.currentJurisdiction {
            truth.lifeState["residence"] = CountryCatalog.shared.displayName(jurisdiction, on: character.currentDate)
        }
        truth.simulationContext = try SimulationContext.render(store: store, geography: geography)
        return truth
    }
}

public struct NarratorRequest: Sendable {
    public var contextRequestID = UUID()
    public var groundTruth: GroundTruth
    /// Trimmed story input, interpreted according to the selected play style.
    public var playerInput: String
    public var fate: Int
    public var targetWords: Int
    public var recentMessages: [ChatMessage]
    public var memory = MemoryContext()
    public var requestedTime: TimeAdvance? = nil
    public var rawFate: Int? = nil

    public init(groundTruth: GroundTruth, playerInput: String, fate: Int, targetWords: Int,
                recentMessages: [ChatMessage]) {
        self.groundTruth = groundTruth
        self.playerInput = playerInput
        self.fate = fate
        self.targetWords = targetWords
        self.recentMessages = recentMessages
    }
}

public struct NarratorResult: Sendable {
    public var output: TurnOutput
    public var inputTokens: Int
    public var outputTokens: Int
    public var contextNotice: String = ""

    public init(output: TurnOutput, inputTokens: Int, outputTokens: Int) {
        self.output = output
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum NarratorError: Error, Equatable, Sendable {
    /// The model's safety systems declined. Not retried.
    case refused
    /// The reply was cut off before the JSON finished.
    case truncated
    case malformedOutput(String)
}

public protocol Narrator: Sendable {
    func narrate(_ request: NarratorRequest) async throws -> NarratorResult
    /// A second attempt after bad output or rejected changes.
    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult
}
