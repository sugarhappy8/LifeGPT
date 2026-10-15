import Foundation

/// Decides when the game itself injects an unexpected event, so lives don't only react to player choices.
public struct EventRoller: Sendable {
    public var chance: Double
    public var random: @Sendable () -> Double

    public init(chance: Double = 0.3, random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.chance = chance
        self.random = random
    }

    static let categories = ["health", "family", "career", "money", "romance", "friendship", "education", "world", "accident", "opportunity"]

    public func roll(for state: GameState) -> EventDirective? {
        guard random() < chance else { return nil }
        var pool = Self.categories
        if state.age < 16 { pool.removeAll { $0 == "career" || $0 == "romance" } }
        let category = pool[min(Int(random() * Double(pool.count)), pool.count - 1)]
        let intensity = random() < 0.2 ? "major" : "minor"
        return EventDirective(category: category, intensity: intensity)
    }
}

/// Runs one turn: compact old history if needed, re-read the saved state into a prompt, ask the model,
/// apply its answer to the state, and save. The returned state is always what was written to disk.
public struct GameEngine: Sendable {
    public var provider: LLMProvider
    public var store: SaveStore
    public var assembler: PromptAssembler
    public var compactor: HistoryCompactor
    public var roller: EventRoller

    public init(
        provider: LLMProvider,
        store: SaveStore,
        assembler: PromptAssembler = PromptAssembler(),
        compactor: HistoryCompactor = HistoryCompactor(),
        roller: EventRoller = EventRoller()
    ) {
        self.provider = provider
        self.store = store
        self.assembler = assembler
        self.compactor = compactor
        self.roller = roller
    }

    public static let openingAction = "Begin my life. Introduce my family and where I am growing up."

    public func playTurn(_ action: String, on state: GameState) async throws -> (GameState, TurnRecord) {
        guard !state.isDead else { throw LifeGPTError.characterIsDead }
        var next = state

        if compactor.needsCompaction(next) {
            try await compactor.compact(&next, using: provider)
            try store.save(next)
        }

        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let directive = next.turns.isEmpty ? nil : roller.roll(for: next)
        let prompt = assembler.assemble(state: next, playerAction: trimmed, directive: directive)
        let reply = try await provider.complete(LLMRequest(system: prompt.system, user: prompt.user, jsonSchema: TurnResult.jsonSchema))
        let result = try TurnResult.decode(from: reply)

        let record = StateApplier.apply(result, playerAction: trimmed.isEmpty ? "Let time pass" : trimmed, to: &next)
        try store.save(next)
        return (next, record)
    }
}

/// Inputs from the new-life screen.
public struct NewLifeOptions: Sendable {
    public var name: String
    public var gender: String
    public var birthYear: Int
    public var birthplace: String
    public var currency: String

    public init(name: String, gender: String, birthYear: Int, birthplace: String, currency: String = "USD") {
        self.name = name
        self.gender = gender
        self.birthYear = birthYear
        self.birthplace = birthplace
        self.currency = currency
    }

    public func makeState(random: () -> Double = { Double.random(in: 0..<1) }) -> GameState {
        func roll(_ lo: Int, _ hi: Int) -> Int { lo + Int(random() * Double(hi - lo + 1)).clamped(0, hi - lo) }
        let born = GameDate(year: birthYear, month: roll(1, 12))
        return GameState(
            character: PlayerCharacter(name: name, gender: gender, birthDate: born, birthplace: birthplace),
            world: World(currentDate: born, location: birthplace, currency: currency),
            stats: Stats(health: roll(60, 100), happiness: roll(50, 90), smarts: roll(20, 90), looks: roll(20, 90))
        )
    }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), hi) }
}
