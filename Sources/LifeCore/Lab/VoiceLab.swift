import Foundation

// MARK: Scenarios and seed

/// One thing a player might type, and what the engine should hold the line on.
public struct VoiceScenario: Codable, Equatable, Sendable {
    public struct Expect: Codable, Equatable, Sendable {
        /// The most money (minor units) the turn may add to the balance.
        public var maxAcceptedGainMinor: Int64?
        /// true: nothing financial may happen; false: something financial must.
        public var noMoneyEntries: Bool?

        public init(maxAcceptedGainMinor: Int64? = nil, noMoneyEntries: Bool? = nil) {
            self.maxAcceptedGainMinor = maxAcceptedGainMinor
            self.noMoneyEntries = noMoneyEntries
        }
    }

    public var id: String
    public var input: String
    public var expect: Expect

    public init(id: String, input: String, expect: Expect) {
        self.id = id
        self.input = input
        self.expect = expect
    }

    public static func load(from url: URL) throws -> [VoiceScenario] {
        try OutputCoding.decoder.decode([VoiceScenario].self, from: Data(contentsOf: url))
    }
}

/// A starting life for the voice lab: a character plus some history.
public struct VoiceSeed: Codable, Sendable {
    public struct SeedCharacter: Codable, Sendable {
        public var name: String
        public var birthplace: String
        public var birthYear: Int
        public var appearance: String
        public var startingAge: Int
        public var background: String?
        public var familyWealthTier: WealthTier?
    }

    public var character: SeedCharacter
    public var cast: [CastUpdate]
    public var decisions: [DecisionRecord]
    public var lifeState: [LifeStateChange]

    public static func load(from url: URL) throws -> VoiceSeed {
        try OutputCoding.decoder.decode(VoiceSeed.self, from: Data(contentsOf: url))
    }

    /// A fresh chat (with the sample US 2005 economy) holding this seed's history.
    public func makeChat(in library: ChatLibrary) throws -> LifeStore {
        let c = character
        let new = NewCharacter(name: c.name, birthplace: c.birthplace, birthYear: c.birthYear,
                               appearance: c.appearance, startingAge: c.startingAge, background: c.background,
                               familyWealthTier: c.familyWealthTier ?? .middle)
        let (_, store) = try library.createChat(character: new, economy: .sampleUS2005)
        try store.seedHistory(cast: cast, decisions: decisions, lifeState: lifeState)
        return store
    }
}

// MARK: Outcomes

public struct ScenarioOutcome: Codable, Equatable, Sendable {
    public var id: String
    /// false when the narrator's first reply was unusable and needed a repair.
    public var jsonValidFirstTry: Bool
    /// Money the turn actually added (positive narrator-origin ledger entries).
    public var acceptedGainMinor: Int64
    /// The largest single gain the narrator proposed, accepted or rejected.
    public var attemptedGainMinor: Int64
    public var rejections: [String]
    public var pass: Bool
    public var inputTokens: Int
    public var outputTokens: Int
    public var error: String?

    public init(id: String, jsonValidFirstTry: Bool, acceptedGainMinor: Int64, attemptedGainMinor: Int64,
                rejections: [String], pass: Bool, inputTokens: Int, outputTokens: Int, error: String? = nil) {
        self.id = id
        self.jsonValidFirstTry = jsonValidFirstTry
        self.acceptedGainMinor = acceptedGainMinor
        self.attemptedGainMinor = attemptedGainMinor
        self.rejections = rejections
        self.pass = pass
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.error = error
    }
}

public enum ScenarioEvaluator {
    /// Scores one finished turn. Expects a chat that holds only this turn's
    /// narrator-origin ledger entries (a fresh chat per run).
    public static func evaluate(_ scenario: VoiceScenario, result: TurnResult, store: LifeStore,
                                log: TurnLog) throws -> ScenarioOutcome {
        let narratorEntries = try store.ledger(limit: 1_000).filter { $0.origin == .narrator }
        let streams = try store.incomeStreams()
        let narratorGains = narratorEntries.map(\.amountMinor).filter { $0 > 0 }
        let accepted = narratorGains.reduce(0, +)
        let attempted = (narratorGains + log.rejections.compactMap(rejectedGain)).max() ?? 0
        let hasFinancialActivity = !narratorEntries.isEmpty || !streams.isEmpty

        var pass = true
        if let limit = scenario.expect.maxAcceptedGainMinor, accepted > limit { pass = false }
        if let none = scenario.expect.noMoneyEntries, none == hasFinancialActivity { pass = false }

        return ScenarioOutcome(
            id: scenario.id,
            jsonValidFirstTry: !log.rejections.contains { $0.hasPrefix("narrator output: ") },
            acceptedGainMinor: accepted, attemptedGainMinor: attempted, rejections: log.rejections,
            pass: pass, inputTokens: log.inputTokens, outputTokens: log.outputTokens)
    }

    /// Rejection lines look like `money side_hustle 20000000000: reason`.
    private static func rejectedGain(_ line: String) -> Int64? {
        guard line.hasPrefix("money "),
              let colon = line.firstIndex(of: ":"),
              let amount = line[..<colon].split(separator: " ").last.flatMap({ Int64($0) }),
              amount > 0
        else { return nil }
        return amount
    }
}

// MARK: Cost

public enum VoiceCost {
    /// Rough USD range: each call assumed ~4k input and ~4k output tokens,
    /// and in the worst case every turn needs one repair call. Nil for models
    /// without a known price.
    public static func estimateUSD(model: String, calls: Int) -> ClosedRange<Double>? {
        let perMillion: [String: (input: Double, output: Double)] = [
            "claude-opus-5-5": (4.0, 20.0),
            "claude-sonnet-5-5": (2.0, 10.0),
            "claude-haiku-5-5": (0.10, 0.50),
        ]
        guard let price = perMillion[model] else { return nil }
        let perCall = 4_000 * price.input / 1_000_000 + 4_000 * price.output / 1_000_000
        let low = Double(calls) * perCall
        return low...(2 * low)
    }
}
