import Foundation

public struct MemoryContext: Equatable, Sendable {
    public var settings = SessionSettings()
    public var brief: PlaceTimeBrief?
    public var paths: [OpportunityPath] = []
    public var threads: [StoryThread] = []
    public var positions: [FinancialPosition] = []
    public var notes = ""
    public var excerpts: [String] = []
    /// Read-only historical records from the active store, never rendered in full.
    public var records: [ContextRecord] = []
    public var lookupNotice = ""
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
        // Records already supplied as recent binding facts do not need another
        // selection request. The rest remain available regardless of their age.
        let chapters = try store.chapters().reversed().map {
            ContextRecord(id: "chapter:\($0.id)", category: .chapter, date: $0.date, text: $0.text)
        }
        let events = try store.events(limit: Int.max).map {
            ContextRecord(id: "event:\($0.id)", category: .event, date: $0.date, text: "[\($0.importance.rawValue)] \($0.title)")
        }
        let decisions = try store.decisions(limit: Int.max).enumerated().dropFirst(10).map { offset, value in
            ContextRecord(id: "decision:\(offset)", category: .decision, date: value.date,
                          text: "[\(value.importance.rawValue)] \(value.summary); chose \(value.choice)")
        }
        let ledger = try store.ledger(limit: Int.max).dropFirst(10).map {
            ContextRecord(id: "ledger:\($0.id)", category: .ledger, date: $0.date,
                          text: "[\($0.accountId)] \($0.sourceType.rawValue) \($0.amountMinor) minor units; \($0.reason)")
        }
        let recentIDs = Set(try store.recentMessages(limit: 12).map(\.id))
        var messages: [ContextRecord] = []
        var after: Int64 = 0
        while true {
            let page = try store.messages(after: after, limit: 500)
            messages += page.filter { !recentIDs.contains($0.id) }.map {
                ContextRecord(id: "message:\($0.id)", category: .message, date: $0.date,
                              text: "\($0.role.rawValue): \($0.text)")
            }
            guard let last = page.last, last.id > after else { break }
            after = last.id
            if page.count < 500 { break }
        }
        let currentDate = try store.character().currentDate
        let simulation = try store.businessSimulation()
        func json<T: Encodable>(_ value: T) throws -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        let businesses = try simulation.businesses.filter { $0.status != .active }.map {
            ContextRecord(id: "business:\($0.id)", category: .business, date: $0.endedOn ?? $0.openedOn,
                          text: "Historical company (not current ownership): \(try json($0))")
        }
        let obligations = try simulation.obligations.enumerated().filter { $0.element.endedOn != nil && $0.element.endedOn! <= currentDate }.map { index, record in
            ContextRecord(id: "obligation:\(record.id):\(index)", category: .obligation, date: record.effectiveFrom,
                          text: "Past agreement, effective \(record.effectiveFrom.iso) until \(record.endedOn!.iso): \(try json(record))")
        }
        let assessments = try simulation.assessments.map {
            ContextRecord(id: "assessment:\($0.id)", category: .assessment, date: $0.periodEnd,
                          text: "Settled business assessment; retained dated rules: \(try json($0))")
        }
        let sales = try simulation.saleDrafts.filter { $0.confirmedOn != nil }.map {
            ContextRecord(id: "sale:\($0.id)", category: .business, date: $0.confirmedOn!,
                          text: "Confirmed historical sale; transferred accounts are not available funds: \(try json($0))")
        }
        let historical = chapters + events + decisions + ledger + messages + businesses + obligations + assessments + sales
        memory.records = historical.filter { $0.date <= currentDate }
        memory.excerpts = ContextSelector.ranked(memory.records, input: input).prefix(15).map(\.excerpt)
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
        let originalExcerptCount = request.memory.excerpts.count
        while size() > available && !request.memory.excerpts.isEmpty { request.memory.excerpts.removeLast() }
        while size() > available && request.recentMessages.count > 2 { request.recentMessages.removeFirst() }
        while size() > available && request.groundTruth.recentDecisions.count > 2 { request.groundTruth.recentDecisions.removeLast() }
        // Every active relationship and commitment remains binding, even when
        // its name is absent from the action. Never silently drop cast members.
        if size() > available { request.memory.notes = String(request.memory.notes.prefix(600)) }
        if size() > available, var brief = request.memory.brief {
            brief.text = String(brief.text.prefix(1000)); request.memory.brief = brief
        }
        if request.memory.excerpts.count < originalExcerptCount {
            request.memory.lookupNotice += " Some older excerpts were omitted to fit this model's context window; binding current facts were retained."
            while size() > available && !request.memory.excerpts.isEmpty { request.memory.excerpts.removeLast() }
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
