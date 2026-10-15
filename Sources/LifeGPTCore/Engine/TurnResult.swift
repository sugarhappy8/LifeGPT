import Foundation

/// What the AI must return for every narration turn. Every field is required and expressed as a delta
/// or an "empty means unchanged" value, so the schema works with strict structured outputs (no nulls).
public struct TurnResult: Codable, Equatable, Sendable {
    public var narration: String
    public var monthsElapsed: Int
    public var statChanges: StatChanges
    public var financeChanges: FinanceChanges
    public var newOccupation: String
    public var newEducation: String
    public var newLocation: String
    public var newTraits: [String]
    public var events: [LifeEvent]
    public var relationshipChanges: [RelationshipChange]
    public var timelineEntries: [NewTimelineEntry]
    public var choices: [String]
    public var died: Bool
    public var causeOfDeath: String

    public struct StatChanges: Codable, Equatable, Sendable {
        public var health: Int
        public var happiness: Int
        public var smarts: Int
        public var looks: Int

        public init(health: Int = 0, happiness: Int = 0, smarts: Int = 0, looks: Int = 0) {
            self.health = health
            self.happiness = happiness
            self.smarts = smarts
            self.looks = looks
        }
    }

    public struct FinanceChanges: Codable, Equatable, Sendable {
        /// One-off cash change on top of the automatic income/expense accrual.
        public var oneOffCash: Double
        public var annualIncomeChange: Double
        public var annualExpensesChange: Double
        public var debtChange: Double

        public init(oneOffCash: Double = 0, annualIncomeChange: Double = 0, annualExpensesChange: Double = 0, debtChange: Double = 0) {
            self.oneOffCash = oneOffCash
            self.annualIncomeChange = annualIncomeChange
            self.annualExpensesChange = annualExpensesChange
            self.debtChange = debtChange
        }
    }

    public struct RelationshipChange: Codable, Equatable, Sendable {
        public var name: String
        public var relation: String
        public var closenessChange: Int
        /// "active", "estranged", "deceased" or "unchanged".
        public var status: String
        public var note: String

        public init(name: String, relation: String, closenessChange: Int, status: String = "unchanged", note: String = "") {
            self.name = name
            self.relation = relation
            self.closenessChange = closenessChange
            self.status = status
            self.note = note
        }
    }

    public struct NewTimelineEntry: Codable, Equatable, Sendable {
        public var title: String
        public var summary: String
        public var importance: Int

        public init(title: String, summary: String, importance: Int) {
            self.title = title
            self.summary = summary
            self.importance = importance
        }
    }

    public init(
        narration: String,
        monthsElapsed: Int,
        statChanges: StatChanges = StatChanges(),
        financeChanges: FinanceChanges = FinanceChanges(),
        newOccupation: String = "",
        newEducation: String = "",
        newLocation: String = "",
        newTraits: [String] = [],
        events: [LifeEvent] = [],
        relationshipChanges: [RelationshipChange] = [],
        timelineEntries: [NewTimelineEntry] = [],
        choices: [String] = [],
        died: Bool = false,
        causeOfDeath: String = ""
    ) {
        self.narration = narration
        self.monthsElapsed = monthsElapsed
        self.statChanges = statChanges
        self.financeChanges = financeChanges
        self.newOccupation = newOccupation
        self.newEducation = newEducation
        self.newLocation = newLocation
        self.newTraits = newTraits
        self.events = events
        self.relationshipChanges = relationshipChanges
        self.timelineEntries = timelineEntries
        self.choices = choices
        self.died = died
        self.causeOfDeath = causeOfDeath
    }

    /// Decodes a model reply, tolerating code fences or prose around the JSON object.
    public static func decode(from text: String) throws -> TurnResult {
        try JSONExtraction.decode(TurnResult.self, from: text)
    }

    // MARK: Schema

    public static var jsonSchema: JSONValue {
        func obj(_ props: [String: JSONValue]) -> JSONValue {
            [
                "type": "object",
                "properties": .object(props),
                "required": .array(props.keys.sorted().map { .string($0) }),
                "additionalProperties": false,
            ]
        }
        let str: JSONValue = ["type": "string"]
        let int: JSONValue = ["type": "integer"]
        let num: JSONValue = ["type": "number"]
        func arr(_ items: JSONValue) -> JSONValue { ["type": "array", "items": items] }

        return obj([
            "narration": str,
            "monthsElapsed": int,
            "statChanges": obj(["health": int, "happiness": int, "smarts": int, "looks": int]),
            "financeChanges": obj([
                "oneOffCash": num, "annualIncomeChange": num, "annualExpensesChange": num, "debtChange": num,
            ]),
            "newOccupation": str,
            "newEducation": str,
            "newLocation": str,
            "newTraits": arr(str),
            "events": arr(obj(["title": str, "description": str, "category": str])),
            "relationshipChanges": arr(obj([
                "name": str, "relation": str, "closenessChange": int,
                "status": ["type": "string", "enum": ["active", "estranged", "deceased", "unchanged"]],
                "note": str,
            ])),
            "timelineEntries": arr(obj(["title": str, "summary": str, "importance": int])),
            "choices": arr(str),
            "died": ["type": "boolean"],
            "causeOfDeath": str,
        ])
    }
}

enum JSONExtraction {
    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw LifeGPTError.malformedResponse("No JSON object in model reply.")
        }
        let data = Data(text[start...end].utf8)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LifeGPTError.malformedResponse("Could not decode model reply: \(error)")
        }
    }
}

public enum LifeGPTError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case malformedResponse(String)
    case provider(String)
    case refused(String)
    case characterIsDead

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your API key in Settings to play."
        case .malformedResponse(let m): return "The AI sent back something the game couldn't read. \(m)"
        case .provider(let m): return m
        case .refused(let m): return "The AI declined this turn. \(m)"
        case .characterIsDead: return "This life has ended. Start a new one."
        }
    }
}
