import Foundation

/// Everything the game knows about one life. This is the single source of truth: it is saved to disk
/// after every turn and re-read in full to build every prompt, so the AI never relies on its own memory.
public struct GameState: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    public var character: PlayerCharacter
    public var world: World
    public var stats: Stats
    public var finances: Finances
    public var relationships: [Relationship]
    /// Major actions and life events worth remembering forever (kept verbatim in every prompt).
    public var timeline: [TimelineEntry]
    /// Every turn played, in order. Old turns are folded into `chapters` and only the recent window is sent verbatim.
    public var turns: [TurnRecord]
    /// Summaries of older stretches of life, produced by the history compactor.
    public var chapters: [ChapterSummary]
    /// Index into `turns` of the first turn not yet folded into a chapter.
    public var firstUnsummarizedTurn: Int
    /// Suggested next actions from the most recent turn.
    public var pendingChoices: [String]
    public var isDead: Bool
    public var causeOfDeath: String?

    public init(
        id: UUID = UUID(),
        character: PlayerCharacter,
        world: World,
        stats: Stats = Stats(),
        finances: Finances = Finances()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.character = character
        self.world = world
        self.stats = stats
        self.finances = finances
        self.relationships = []
        self.timeline = []
        self.turns = []
        self.chapters = []
        self.firstUnsummarizedTurn = 0
        self.pendingChoices = []
        self.isDead = false
        self.causeOfDeath = nil
    }

    public var age: Int { character.birthDate.yearsUntil(world.currentDate) }

    /// Turns not yet folded into a chapter summary.
    public var unsummarizedTurns: ArraySlice<TurnRecord> {
        turns[min(firstUnsummarizedTurn, turns.count)...]
    }
}

public struct PlayerCharacter: Codable, Equatable, Sendable {
    public var name: String
    public var gender: String
    public var birthDate: GameDate
    public var birthplace: String
    public var occupation: String
    public var education: String
    /// Short free-form traits ("stubborn", "musical") the AI can add to.
    public var traits: [String]

    public init(
        name: String,
        gender: String,
        birthDate: GameDate,
        birthplace: String,
        occupation: String = "None",
        education: String = "None",
        traits: [String] = []
    ) {
        self.name = name
        self.gender = gender
        self.birthDate = birthDate
        self.birthplace = birthplace
        self.occupation = occupation
        self.education = education
        self.traits = traits
    }
}

public struct World: Codable, Equatable, Sendable {
    public var currentDate: GameDate
    public var location: String
    /// ISO-ish currency label used in narration, e.g. "USD". Amounts are stored in that currency at period value.
    public var currency: String

    public init(currentDate: GameDate, location: String, currency: String = "USD") {
        self.currentDate = currentDate
        self.location = location
        self.currency = currency
    }
}

/// Classic life-sim meters, each clamped to 0...100.
public struct Stats: Codable, Equatable, Sendable {
    public var health: Int
    public var happiness: Int
    public var smarts: Int
    public var looks: Int

    public init(health: Int = 80, happiness: Int = 70, smarts: Int = 50, looks: Int = 50) {
        self.health = health
        self.happiness = happiness
        self.smarts = smarts
        self.looks = looks
    }
}

/// Money is tracked locally and deterministically: yearly income and expenses accrue as time passes,
/// and the AI only reports one-off changes (a windfall, a fine, a purchase).
public struct Finances: Codable, Equatable, Sendable {
    public var cash: Double
    public var annualIncome: Double
    public var annualExpenses: Double
    public var debt: Double

    public init(cash: Double = 0, annualIncome: Double = 0, annualExpenses: Double = 0, debt: Double = 0) {
        self.cash = cash
        self.annualIncome = annualIncome
        self.annualExpenses = annualExpenses
        self.debt = debt
    }

    public var netWorth: Double { cash - debt }
}

public struct Relationship: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case active, estranged, deceased
    }

    public var id: UUID
    public var name: String
    /// How they relate to the player: "mother", "best friend", "boss", "spouse"...
    public var relation: String
    /// 0...100
    public var closeness: Int
    public var status: Status
    /// Running notes the AI has added, newest last. Trimmed to the most recent few.
    public var notes: [String]

    public init(id: UUID = UUID(), name: String, relation: String, closeness: Int = 50, status: Status = .active, notes: [String] = []) {
        self.id = id
        self.name = name
        self.relation = relation
        self.closeness = closeness
        self.status = status
        self.notes = notes
    }
}

public struct TimelineEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: GameDate
    public var title: String
    public var summary: String
    /// 1 (minor) ... 5 (life-defining). Entries at 4+ are always included in prompts.
    public var importance: Int

    public init(id: UUID = UUID(), date: GameDate, title: String, summary: String, importance: Int) {
        self.id = id
        self.date = date
        self.title = title
        self.summary = summary
        self.importance = importance
    }
}

/// One player action and the AI's answer to it, plus what changed.
public struct TurnRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var dateBefore: GameDate
    public var dateAfter: GameDate
    public var playerAction: String
    public var narration: String
    public var events: [LifeEvent]
    /// Short human-readable list of state changes ("Cash +$1,200", "Health -5").
    public var changeLog: [String]

    public init(id: UUID = UUID(), dateBefore: GameDate, dateAfter: GameDate, playerAction: String, narration: String, events: [LifeEvent], changeLog: [String]) {
        self.id = id
        self.dateBefore = dateBefore
        self.dateAfter = dateAfter
        self.playerAction = playerAction
        self.narration = narration
        self.events = events
        self.changeLog = changeLog
    }
}

public struct LifeEvent: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var category: String

    public init(title: String, description: String, category: String) {
        self.title = title
        self.description = description
        self.category = category
    }
}

public struct ChapterSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var from: GameDate
    public var to: GameDate
    public var text: String

    public init(id: UUID = UUID(), from: GameDate, to: GameDate, text: String) {
        self.id = id
        self.from = from
        self.to = to
        self.text = text
    }
}
