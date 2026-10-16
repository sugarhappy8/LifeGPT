import Foundation
import GRDB

extension LifeStore {
    public func revision() throws -> Int {
        try dbQueue.read { try Int.fetchOne($0, sql: "SELECT revision FROM session") ?? 0 }
    }
    public func hasEnded() throws -> Bool {
        try dbQueue.read { try Bool.fetchOne($0, sql: "SELECT ended FROM session") ?? false }
    }
    public func sessionSettings() throws -> SessionSettings {
        try dbQueue.read { db in
            let json = try String.fetchOne(db, sql: "SELECT settings_json FROM session") ?? "{}"
            return (try? JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))) ?? SessionSettings()
        }
    }
    public func updateSettings(_ settings: SessionSettings, swingDial: Int, replyLengthWords: Int) throws {
        guard (0...3).contains(swingDial), (60...2000).contains(replyLengthWords), settings.voiceBible.count <= 12_000,
              settings.contentTone.count <= 2_000, (0...100).contains(settings.difficulty) else { throw ValidationError.invalid("Story settings are outside the supported range.") }
        let json = try Self.json(settings)
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE session SET settings_json = ?, swing_dial = ?, reply_length_words = ?, revision = revision + 1",
                           arguments: [json, swingDial, replyLengthWords])
        }
    }
    public func authorNotes() throws -> String {
        try dbQueue.read { try String.fetchOne($0, sql: "SELECT author_notes FROM session") ?? "" }
    }
    public func choices() throws -> [String] {
        try dbQueue.read { db in
            let json = try String.fetchOne(db, sql: "SELECT choices_json FROM session") ?? "[]"
            return try JSONDecoder().decode([String].self, from: Data(json.utf8))
        }
    }
    public func events(limit: Int = 200) throws -> [TimelineEvent] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM events ORDER BY id DESC LIMIT ?", arguments: [limit]).map {
                TimelineEvent(id: $0["id"], date: try Self.parseDate($0["date"]), title: $0["title"],
                              importance: Importance(rawValue: $0["importance"]) ?? .minor, uncanny: $0["uncanny"])
            }
        }
    }
    public func placeTimeBriefs() throws -> [PlaceTimeBrief] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM place_time_brief ORDER BY version").map {
                PlaceTimeBrief(version: $0["version"], date: try Self.parseDate($0["date"]), location: $0["location"], text: $0["text"])
            }
        }
    }
    /// The review screen is the only writer of economy versions. Narration cannot change the currency or prices.
    public func saveWorld(brief: PlaceTimeBrief, economy: EconomyCard) throws {
        try economy.validate()
        guard !brief.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !brief.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, brief.text.count <= 24_000 else {
            throw ValidationError.invalid("The world brief needs a location and up to 24,000 characters of context.")
        }
        try dbQueue.write { db in
            if let old = try String.fetchOne(db, sql: "SELECT json FROM economy_card ORDER BY version DESC LIMIT 1") {
                let previous = try JSONDecoder().decode(EconomyCard.self, from: Data(old.utf8))
                guard previous.currency == economy.currency, previous.minorUnitsPerUnit == economy.minorUnitsPerUnit else {
                    throw ValidationError.invalid("Currency cannot change in an existing life without an exchange-rate migration. Keep this life's accounting currency when moving abroad.")
                }
            }
            let next = (try Int.fetchOne(db, sql: "SELECT MAX(version) FROM economy_card") ?? 0) + 1
            var card = economy; card.version = next
            try db.execute(sql: "INSERT INTO economy_card (version, json) VALUES (?, ?)", arguments: [next, try Self.json(card)])
            try db.execute(sql: "INSERT INTO place_time_brief (version, date, location, text) VALUES (?, ?, ?, ?)",
                           arguments: [next, brief.date.iso, brief.location, brief.text])
            try db.execute(sql: "UPDATE session SET revision = revision + 1")
        }
    }
    public func paths() throws -> [OpportunityPath] { try jsonRows("opportunity_paths", as: OpportunityPath.self) }
    public func threads() throws -> [StoryThread] { try jsonRows("story_threads", as: StoryThread.self) }
    public func positions() throws -> [FinancialPosition] {
        let rows = try jsonRows("financial_positions", as: FinancialPosition.self)
        guard rows.count <= 200, rows.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && !$0.name.isEmpty &&
            (0...1_000_000_000_000_000).contains($0.principalMinor) && (0...10_000).contains($0.annualRateBPS) &&
            (0...1_000_000_000_000).contains($0.monthlyPaymentMinor) }) else {
            throw StoreError.corrupt("invalid financial position")
        }
        return rows
    }
    private func jsonRows<T: Decodable>(_ table: String, as type: T.Type) throws -> [T] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM \(table) ORDER BY id").map { try JSONDecoder().decode(type, from: Data($0.utf8)) }
        }
    }
    public func chapters() throws -> [ChapterSummary] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM chapter_summaries ORDER BY id").map {
                ChapterSummary(id: $0["id"], throughMessageID: $0["through_message_id"], date: try Self.parseDate($0["date"]), text: $0["text"])
            }
        }
    }
    public func saveChapter(throughMessageID: Int64, date: GameDate, text: String) throws {
        guard !text.isEmpty, text.count <= 30_000 else { throw ValidationError.invalid("Invalid chapter summary.") }
        try dbQueue.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO chapter_summaries (through_message_id, date, text) VALUES (?, ?, ?)",
                           arguments: [throughMessageID, date.iso, text])
        }
    }
    public func messages(after id: Int64 = 0, limit: Int = 500) throws -> [ChatMessage] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM messages WHERE id > ? ORDER BY id LIMIT ?", arguments: [id, limit]).map {
                ChatMessage(id: $0["id"], role: ChatMessage.Role(rawValue: $0["role"]) ?? .narrator,
                            text: $0["text"], date: try Self.parseDate($0["date"]))
            }
        }
    }
    public func messageCount() throws -> Int {
        try dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM messages") ?? 0 }
    }
    public func saveOpening(_ text: String, choices: [String]) throws {
        try dbQueue.write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages") == 0 else { return }
            let date = try String.fetchOne(db, sql: "SELECT game_date FROM character") ?? ""
            try db.execute(sql: "INSERT INTO messages (role, text, date) VALUES ('narrator', ?, ?)", arguments: [text, date])
            try db.execute(sql: "UPDATE session SET choices_json = ?, revision = revision + 1", arguments: [try Self.json(choices)])
        }
    }
    /// SQLite's backup API includes committed WAL pages; copying the live file alone would lose them.
    public func backup(to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw StoreError.alreadyExists }
        let target = try DatabaseQueue(path: destination.path)
        try dbQueue.backup(to: target)
    }
    static func writeTurnMemory(_ db: Database, turn: AppliedTurn) throws {
        try db.execute(sql: "UPDATE session SET author_notes = ?, choices_json = ?, ended = MAX(ended, ?)",
                       arguments: [String(turn.authorNotes.prefix(12_000)), try json(turn.choices), turn.ended])
        for path in turn.paths {
            try db.execute(sql: "INSERT INTO opportunity_paths (id, json) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json",
                           arguments: [path.id, try json(path)])
        }
        for thread in turn.threads {
            try db.execute(sql: "INSERT INTO story_threads (id, json) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json",
                           arguments: [thread.id, try json(thread)])
        }
        if let positions = turn.positions {
            try db.execute(sql: "DELETE FROM financial_positions")
            for p in positions {
                try db.execute(sql: "INSERT INTO financial_positions (id, json) VALUES (?, ?)", arguments: [p.id, try json(p)])
            }
        }
    }
    static func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}

extension LifeStore {
    public func sideHustleTotal(since date: GameDate) throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM ledger WHERE source_type = 'side_hustle' AND origin = 'narrator' AND date >= ?", arguments: [date.iso]) ?? 0
        }
    }
}

extension LifeStore {
    func assignIdentity(_ id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE session SET id = ?, last_played = ?", arguments: [id.uuidString, Date().timeIntervalSince1970])
            try db.execute(sql: "UPDATE character SET id = ?", arguments: [id.uuidString])
        }
    }
}

extension LifeStore {
    /// Import the source without migrating or writing it. Migration belongs to the independent copy.
    static func copyForImport(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw StoreError.notAStore }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw StoreError.alreadyExists }
        var configuration = Configuration(); configuration.readonly = true
        let original = try DatabaseQueue(path: source.path, configuration: configuration)
        let version = try original.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 }
        guard version > 0 else { throw StoreError.notAStore }
        guard version <= Schema.version else { throw StoreError.unsupportedSchema(found: version) }
        let copy = try DatabaseQueue(path: destination.path)
        try original.backup(to: copy)
    }
}
