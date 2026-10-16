import Foundation

public struct MemoryContext: Equatable, Sendable {
    public var settings = SessionSettings()
    public var brief: PlaceTimeBrief?
    public var paths: [OpportunityPath] = []
    public var threads: [StoryThread] = []
    public var positions: [FinancialPosition] = []
    public var notes = ""
    public var excerpts: [String] = []
    public init() {}
}

public enum ContextBuilder {
    public static func memory(store: LifeStore, input: String) throws -> MemoryContext {
        var memory = MemoryContext()
        memory.settings = try store.sessionSettings()
        memory.brief = try store.placeTimeBriefs().last
        memory.paths = try store.paths()
        memory.threads = try store.threads().filter { !$0.resolved }
        memory.positions = try store.positions().filter { $0.principalMinor > 0 }
        memory.notes = try store.authorNotes()
        let chapters = try store.chapters().reversed().map { "Chapter through \($0.date.iso): \($0.text)" }
        let events = try store.events(limit: 200).map { "\($0.date.iso) [\($0.importance.rawValue)] \($0.title)" }
        let decisions = try store.decisions(limit: 500).map { "\($0.date.iso) [\($0.importance.rawValue)] Decision: \($0.summary); chose \($0.choice)" }
        memory.excerpts = ranked(decisions + chapters + events, matching: input).prefix(15).map { $0 }
        return memory
    }

    /// UTF-8 byte count is deliberately conservative for multilingual prose.
    public static func estimatedTokens(_ text: String) -> Int { (text.utf8.count + 2) / 3 }

    public static func budget(_ original: NarratorRequest, contextTokens: Int, outputTokens: Int,
                              rejections: [String], formatOverhead: String = "") throws -> NarratorRequest {
        var request = original
        let available = max(0, contextTokens - outputTokens - 1000)
        request.groundTruth.cast = request.groundTruth.cast.sorted {
            let a = score($0.name + " " + ($0.notes ?? ""), matching: request.playerInput)
            let b = score($1.name + " " + ($1.notes ?? ""), matching: request.playerInput)
            if a != b { return a > b }
            if $0.lastSeen != $1.lastSeen { return $0.lastSeen > $1.lastSeen }
            return $0.name < $1.name
        }
        func size() -> Int {
            let p = PromptRenderer.render(request, rejections: rejections)
            return estimatedTokens(p.system + p.user + OutputSchema.json + formatOverhead)
        }
        // Trim auxiliary context, never the player's current input, identity, date or financial ground truth.
        while size() > available && !request.memory.excerpts.isEmpty { request.memory.excerpts.removeLast() }
        while size() > available && request.recentMessages.count > 2 { request.recentMessages.removeFirst() }
        while size() > available && request.groundTruth.recentDecisions.count > 2 { request.groundTruth.recentDecisions.removeLast() }
        while size() > available && request.groundTruth.cast.count > 4 { request.groundTruth.cast.removeLast(max(1, (request.groundTruth.cast.count - 4) / 2)) }
        if size() > available { request.memory.notes = String(request.memory.notes.prefix(600)) }
        if size() > available, var brief = request.memory.brief {
            brief.text = String(brief.text.prefix(1000)); request.memory.brief = brief
        }
        guard size() <= available else {
            throw ValidationError.invalid("This life's essential context exceeds the model's configured context window. Increase the context size in Settings, shorten the voice/background, or use a larger-context model.")
        }
        return request
    }
    public static func ranked(_ texts: [String], matching input: String) -> [String] {
        texts.enumerated().sorted {
            let a = score($0.element, matching: input), b = score($1.element, matching: input)
            return a == b ? $0.offset < $1.offset : a > b
        }.map(\.element)
    }
    private static func score(_ text: String, matching input: String) -> Int {
        let words = Set(input.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count > 2 })
        let haystack = text.lowercased()
        return words.reduce(haystack.contains("[major]") ? 4 : 0) { $0 + (haystack.contains($1) ? 5 : 0) }
    }
}
