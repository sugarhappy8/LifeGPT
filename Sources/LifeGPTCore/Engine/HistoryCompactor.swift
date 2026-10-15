import Foundation

/// Keeps prompts bounded as a life gets long. Recent turns stay verbatim; older turns are folded into
/// chapter summaries by the model, and once there are too many chapters the oldest are merged again.
/// Timeline entries (major moments) are never summarized away, so the facts that matter survive.
public struct HistoryCompactor: Sendable {
    /// Turns always kept verbatim (should be >= the assembler's recentTurns).
    public var keepRecent: Int
    /// How many old turns to fold at once.
    public var batchSize: Int
    /// When chapters exceed this, the oldest `chapterMergeCount` are merged into one.
    public var maxChapters: Int
    public var chapterMergeCount: Int

    public init(keepRecent: Int = 8, batchSize: Int = 8, maxChapters: Int = 10, chapterMergeCount: Int = 4) {
        self.keepRecent = keepRecent
        self.batchSize = batchSize
        self.maxChapters = maxChapters
        self.chapterMergeCount = chapterMergeCount
    }

    static let systemPrompt = """
    You compress the history of a life simulation game into a concise chapter summary. Keep every concrete \
    fact the story may depend on later: names and relationships, money gained or lost, jobs, schooling, moves, \
    illnesses, promises, conflicts and their outcomes, and the character's emotional state. Drop atmosphere and \
    repetition. Write in third person past tense, one paragraph, at most 180 words. Reply with only the summary.
    """

    public func needsCompaction(_ state: GameState) -> Bool {
        state.unsummarizedTurns.count >= keepRecent + batchSize || state.chapters.count > maxChapters
    }

    /// Runs as many compaction steps as needed. Mutates `state` only after each successful model call.
    public func compact(_ state: inout GameState, using provider: LLMProvider) async throws {
        while state.unsummarizedTurns.count >= keepRecent + batchSize {
            let start = state.firstUnsummarizedTurn
            let batch = Array(state.turns[start..<(start + batchSize)])
            let text = try await provider.complete(LLMRequest(
                system: Self.systemPrompt,
                user: Self.turnsPrompt(character: state.character.name, turns: batch),
                maxTokens: 2_000
            ))
            state.chapters.append(ChapterSummary(from: batch.first!.dateBefore, to: batch.last!.dateAfter, text: Self.clean(text)))
            state.firstUnsummarizedTurn = start + batchSize
        }
        while state.chapters.count > maxChapters {
            let group = Array(state.chapters.prefix(chapterMergeCount))
            let text = try await provider.complete(LLMRequest(
                system: Self.systemPrompt,
                user: Self.chaptersPrompt(character: state.character.name, chapters: group),
                maxTokens: 2_000
            ))
            let merged = ChapterSummary(from: group.first!.from, to: group.last!.to, text: Self.clean(text))
            state.chapters.replaceSubrange(0..<group.count, with: [merged])
        }
    }

    static func turnsPrompt(character: String, turns: [TurnRecord]) -> String {
        var out = "Summarize this stretch of \(character)'s life.\n"
        for t in turns {
            out += "\n\(t.dateBefore) to \(t.dateAfter). Player chose: \(t.playerAction)\n\(t.narration)\n"
            if !t.changeLog.isEmpty { out += "Changes: \(t.changeLog.joined(separator: "; "))\n" }
        }
        return out
    }

    static func chaptersPrompt(character: String, chapters: [ChapterSummary]) -> String {
        "Merge these consecutive chapters of \(character)'s life into one chapter summary.\n\n"
            + chapters.map { "\($0.from) to \($0.to): \($0.text)" }.joined(separator: "\n\n")
    }

    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
