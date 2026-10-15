import Foundation

/// A provider-neutral prompt: a stable system prompt plus one user message rebuilt from saved state.
public struct AssembledPrompt: Equatable, Sendable {
    public var system: String
    public var user: String
}

/// Nudge from the game to the AI that something unplanned should happen this turn.
public struct EventDirective: Equatable, Sendable {
    public var category: String
    public var intensity: String

    public init(category: String, intensity: String) {
        self.category = category
        self.intensity = intensity
    }
}

/// Builds every narration prompt from the saved `GameState`. Nothing is carried over from previous API calls:
/// the full character sheet, money, people, major events and story so far are re-read from local state each turn.
public struct PromptAssembler: Sendable {
    public struct Budget: Sendable {
        /// Rough cap on the user message size (characters; ~4 characters per token).
        public var maxCharacters: Int
        /// How many recent turns are included word for word.
        public var recentTurns: Int
        /// Minimum recent turns kept even when trimming to fit.
        public var minRecentTurns: Int

        public init(maxCharacters: Int = 60_000, recentTurns: Int = 8, minRecentTurns: Int = 2) {
            self.maxCharacters = maxCharacters
            self.recentTurns = recentTurns
            self.minRecentTurns = minRecentTurns
        }
    }

    public var budget: Budget

    public init(budget: Budget = Budget()) {
        self.budget = budget
    }

    public static let systemPrompt = """
    You are the narrator and game master of LifeGPT, a text life simulation. The player lives one life from \
    childhood to death, one turn at a time. Each turn you receive the complete saved state of their life and \
    the action they chose, and you narrate what happens next.

    How to narrate:
    - Write in second person ("you"), present tense, 1 to 3 short paragraphs. Vivid, specific, grounded.
    - The time period and place matter. Prices, wages, technology, jobs, slang, laws, social norms and world \
    events must fit the current in-game date and location. Never mention things that do not exist yet.
    - Respect the saved state as canon: names, relationships, money, past events. Do not contradict it.
    - The player's action is an intention, not a guarantee. Outcomes depend on age, stats, money, era and luck. \
    A 6-year-old cannot buy a car; a poor character cannot buy a mansion.
    - Introduce events of your own when it fits: people entering or leaving their life, illness, opportunities, \
    accidents, historical events touching their life. When the game asks for an unexpected event, include one.
    - Choose how much time passes (monthsElapsed). Usually 1 to 12 months; up to 60 when the action is \
    "skip ahead" or nothing much happens. Keep childhood brisk.

    How to report changes (the game applies them; you never edit numbers directly in prose):
    - statChanges are deltas, usually between -15 and +15.
    - financeChanges: oneOffCash is a one-time gain or loss. Regular pay and living costs are applied automatically \
    from annual income and expenses, so change annualIncomeChange/annualExpensesChange when a job, rent or lifestyle \
    changes instead of adding salary as oneOffCash. Amounts are in the stated currency at period-accurate values.
    - Use empty strings for newOccupation/newEducation/newLocation when they do not change.
    - relationshipChanges: include anyone new (give them a name and relation) and anyone whose bond changed. \
    Use status "unchanged" unless they became estranged or died.
    - timelineEntries: only genuinely memorable moments (first job, marriage, a death, a move). importance 1-5.
    - events: notable things that happened this turn, each with a short category such as health, family, career, \
    money, romance, education, world, accident, opportunity.
    - choices: 3 or 4 short, distinct actions the player might take next, fitting their age and situation.
    - Set died to true only when the character dies, with a causeOfDeath. Old age, illness and risk should make death \
    plausible eventually.
    """

    public func assemble(state: GameState, playerAction: String, directive: EventDirective?) -> AssembledPrompt {
        var chapters = state.chapters
        var timeline = state.timeline
        var recentCount = min(budget.recentTurns, state.unsummarizedTurns.count)

        func build() -> String {
            var parts: [String] = []
            parts.append(characterSection(state))
            parts.append(worldSection(state))
            parts.append(peopleSection(state))
            if !chapters.isEmpty { parts.append(chaptersSection(chapters)) }
            if !timeline.isEmpty { parts.append(timelineSection(timeline)) }
            let recent = Array(state.unsummarizedTurns.suffix(recentCount))
            let skipped = state.unsummarizedTurns.count - recent.count
            if !recent.isEmpty { parts.append(recentSection(recent, omitted: skipped)) }
            if let directive { parts.append(directiveSection(directive)) }
            parts.append("## Player action\n\(playerAction.isEmpty ? "(The player lets time pass.)" : playerAction)")
            return parts.joined(separator: "\n\n")
        }

        var text = build()
        // Trim to budget: oldest chapter summaries first, then minor timeline entries, then old verbatim turns.
        while text.count > budget.maxCharacters {
            if chapters.count > 1 {
                chapters.removeFirst()
            } else if let i = indexOfLeastImportant(timeline) {
                timeline.remove(at: i)
            } else if recentCount > budget.minRecentTurns {
                recentCount -= 1
            } else {
                break
            }
            text = build()
        }
        return AssembledPrompt(system: Self.systemPrompt, user: text)
    }

    /// Lowest-importance, oldest entry below importance 4. Life-defining entries are never trimmed.
    private func indexOfLeastImportant(_ timeline: [TimelineEntry]) -> Int? {
        timeline.indices
            .filter { timeline[$0].importance < 4 }
            .min { (timeline[$0].importance, $0) < (timeline[$1].importance, $1) }
    }

    // MARK: Sections

    private func characterSection(_ s: GameState) -> String {
        let c = s.character
        let f = s.finances
        return """
        ## Character
        Name: \(c.name)
        Gender: \(c.gender)
        Born: \(c.birthDate) in \(c.birthplace)
        Age: \(s.age)
        Occupation: \(c.occupation)
        Education: \(c.education)
        Traits: \(c.traits.isEmpty ? "none yet" : c.traits.joined(separator: ", "))
        Stats (0-100): health \(s.stats.health), happiness \(s.stats.happiness), smarts \(s.stats.smarts), looks \(s.stats.looks)
        Money (\(s.world.currency)): cash \(formatMoney(f.cash)), annual income \(formatMoney(f.annualIncome)), \
        annual expenses \(formatMoney(f.annualExpenses)), debt \(formatMoney(f.debt))
        """
    }

    private func worldSection(_ s: GameState) -> String {
        """
        ## World
        Current date: \(s.world.currentDate)
        Location: \(s.world.location)
        Era: \(EraGuide.notes(for: s.world.currentDate.year))
        """
    }

    private func peopleSection(_ s: GameState) -> String {
        guard !s.relationships.isEmpty else { return "## People\nNo one recorded yet. Introduce family as the story needs." }
        let lines = s.relationships.map { r -> String in
            var line = "- \(r.name), \(r.relation), closeness \(r.closeness)"
            if r.status != .active { line += ", \(r.status.rawValue)" }
            if !r.notes.isEmpty { line += ". " + r.notes.suffix(3).joined(separator: " ") }
            return line
        }
        return "## People\n" + lines.joined(separator: "\n")
    }

    private func chaptersSection(_ chapters: [ChapterSummary]) -> String {
        "## Life so far (summarized)\n" + chapters.map { "\($0.from) to \($0.to): \($0.text)" }.joined(separator: "\n\n")
    }

    private func timelineSection(_ timeline: [TimelineEntry]) -> String {
        "## Major moments\n" + timeline.map { "- \($0.date) [\($0.importance)] \($0.title): \($0.summary)" }.joined(separator: "\n")
    }

    private func recentSection(_ turns: [TurnRecord], omitted: Int) -> String {
        var out = "## Recent turns (oldest first)"
        if omitted > 0 { out += "\n(\(omitted) earlier turns omitted for length.)" }
        for t in turns {
            out += "\n\n\(t.dateBefore) | Player: \(t.playerAction)\n\(t.narration)"
        }
        return out
    }

    private func directiveSection(_ d: EventDirective) -> String {
        "## Game directive\nIntroduce one unexpected \(d.intensity) event this turn, category: \(d.category). Make it fit the era, place and the character's situation."
    }
}
