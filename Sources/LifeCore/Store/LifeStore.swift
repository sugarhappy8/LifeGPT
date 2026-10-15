import Foundation
import GRDB

/// One chat's database: a single SQLite file holding the character, ledger,
/// cast, decisions, and transcript. Nothing in it is shared with another chat.
public final class LifeStore: Sendable {
    public let url: URL
    private let dbQueue: DatabaseQueue

    private init(url: URL, dbQueue: DatabaseQueue) {
        self.url = url
        self.dbQueue = dbQueue
    }

    // MARK: Create and open

    public static func create(at url: URL, character: NewCharacter, economy: EconomyCard,
                              id: UUID = UUID()) throws -> LifeStore {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw StoreError.alreadyExists }
        let queue = try DatabaseQueue(path: url.path)
        try Schema.migrate(queue)

        let c = Character(from: character, id: id)
        let now = Date().timeIntervalSince1970
        let economyJSON = String(decoding: try JSONEncoder().encode(economy), as: UTF8.self)
        let opening = StartingMoney.balanceMinor(forAge: character.startingAge, economy: economy)

        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO session (id, schema_version, created_at, last_played, swing_dial, reply_length_words)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id.uuidString, Schema.version, now, now, c.swingDial, c.replyLengthWords])
            try db.execute(
                sql: """
                    INSERT INTO character (id, name, birthplace, birth_year, appearance, starting_age,
                                           background, family_wealth_tier, birth_date, game_date)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id.uuidString, c.name, c.birthplace, c.birthYear, c.appearance, c.startingAge,
                            c.background, c.familyWealthTier.rawValue, c.birthDate.iso, c.currentDate.iso])
            try db.execute(sql: "INSERT INTO economy_card (version, json) VALUES (?, ?)",
                           arguments: [economy.version, economyJSON])
            try db.execute(
                sql: """
                    INSERT INTO ledger (date, source_type, amount_minor, reason, counterparty,
                                        balance_after_minor, origin)
                    VALUES (?, ?, ?, ?, NULL, ?, ?)
                    """,
                arguments: [c.currentDate.iso, SourceType.opening.rawValue, opening, "Starting savings",
                            opening, Origin.engine.rawValue])
        }
        return LifeStore(url: url, dbQueue: queue)
    }

    public static func open(at url: URL) throws -> LifeStore {
        guard try hasSQLiteHeader(url) else { throw StoreError.notAStore }
        let queue: DatabaseQueue
        let version: Int
        do {
            queue = try DatabaseQueue(path: url.path)
            version = try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 }
        } catch is DatabaseError {
            throw StoreError.notAStore
        }
        if version == 0 { throw StoreError.notAStore }
        if version != Schema.version { throw StoreError.unsupportedSchema(found: version) }
        return LifeStore(url: url, dbQueue: queue)
    }

    private static func hasSQLiteHeader(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 16) ?? Data()
        return header == Data("SQLite format 3\0".utf8)
    }

    // MARK: Reads

    public func character() throws -> Character {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT c.*, s.swing_dial, s.reply_length_words FROM character c, session s
                """) else { throw StoreError.corrupt("missing character") }
            let new = NewCharacter(
                name: row["name"], birthplace: row["birthplace"], birthYear: row["birth_year"],
                appearance: row["appearance"], startingAge: row["starting_age"], background: row["background"],
                familyWealthTier: WealthTier(rawValue: row["family_wealth_tier"]) ?? .middle,
                swingDial: row["swing_dial"], replyLengthWords: row["reply_length_words"])
            var c = Character(from: new, id: UUID(uuidString: row["id"]) ?? UUID())
            c.birthDate = try Self.parseDate(row["birth_date"])
            c.currentDate = try Self.parseDate(row["game_date"])
            return c
        }
    }

    public func economy() throws -> EconomyCard {
        try dbQueue.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT json FROM economy_card ORDER BY version DESC LIMIT 1")
            else { throw StoreError.corrupt("missing economy card") }
            return try JSONDecoder().decode(EconomyCard.self, from: Data(json.utf8))
        }
    }

    public func lastPlayed() throws -> Date {
        try dbQueue.read { db in
            let t = try Double.fetchOne(db, sql: "SELECT last_played FROM session") ?? 0
            return Date(timeIntervalSince1970: t)
        }
    }

    public func balanceMinor() throws -> Int64 {
        try dbQueue.read { try Self.balance($0) }
    }

    /// Newest first.
    public func ledger(limit: Int) throws -> [LedgerEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM ledger ORDER BY id DESC LIMIT ?", arguments: [limit]).map { row in
                LedgerEntry(id: row["id"], date: try Self.parseDate(row["date"]),
                            sourceType: SourceType(rawValue: row["source_type"]) ?? .expense,
                            amountMinor: row["amount_minor"], reason: row["reason"],
                            counterparty: row["counterparty"],
                            origin: Origin(rawValue: row["origin"]) ?? .engine,
                            balanceAfterMinor: row["balance_after_minor"])
            }
        }
    }

    public func lastLedgerDate(source: SourceType) throws -> GameDate? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT MAX(date) FROM ledger WHERE source_type = ?",
                                arguments: [source.rawValue]).map(Self.parseDate)
        }
    }

    /// Most recent gift or inheritance from `giver` (case-insensitive).
    public func lastGiftDate(from giver: String) throws -> GameDate? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT MAX(date) FROM ledger
                WHERE source_type IN ('gift', 'inheritance') AND counterparty = ? COLLATE NOCASE
                """, arguments: [giver]).map(Self.parseDate)
        }
    }

    /// Every stream ever started, oldest first (ended ones keep `endedOn`).
    public func incomeStreams() throws -> [IncomeStream] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM income_streams ORDER BY id").map { row in
                IncomeStream(name: row["name"],
                             kind: IncomeStream.Kind(rawValue: row["kind"]) ?? .wage,
                             tier: row["tier"], monthlyMinor: row["monthly_minor"],
                             startedOn: try Self.parseDate(row["started_on"]),
                             endedOn: try (row["ended_on"] as String?).map(Self.parseDate))
            }
        }
    }

    public func castMembers() throws -> [CastMember] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM cast_members ORDER BY id").map { row in
                CastMember(name: row["name"], relation: row["relation"], notes: row["notes"],
                           status: row["status"], firstMet: try Self.parseDate(row["first_met"]),
                           lastSeen: try Self.parseDate(row["last_seen"]))
            }
        }
    }

    /// Newest first.
    public func decisions(limit: Int) throws -> [DecisionRow] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM decisions ORDER BY id DESC LIMIT ?", arguments: [limit]).map { row in
                DecisionRow(date: try Self.parseDate(row["date"]), summary: row["summary"], choice: row["choice"],
                            importance: Importance(rawValue: row["importance"]) ?? .minor)
            }
        }
    }

    public func lifeState() throws -> [String: String] {
        try dbQueue.read { db in
            var state: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, value FROM life_state") {
                state[row["key"]] = row["value"]
            }
            return state
        }
    }

    /// The last `limit` messages, oldest first.
    public func recentMessages(limit: Int) throws -> [ChatMessage] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM (SELECT * FROM messages ORDER BY id DESC LIMIT ?) ORDER BY id ASC
                """, arguments: [limit]).map { row in
                ChatMessage(id: row["id"], role: ChatMessage.Role(rawValue: row["role"]) ?? .narrator,
                            text: row["text"], date: try Self.parseDate(row["date"]))
            }
        }
    }

    /// Oldest first.
    public func turnLogs() throws -> [TurnLog] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM turn_log ORDER BY id").map { row in
                let json: String = row["rejections_json"]
                let rejections = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
                return TurnLog(fate: row["fate"], rejections: rejections, repaired: row["repaired"],
                               inputTokens: row["input_tokens"], outputTokens: row["output_tokens"])
            }
        }
    }

    // MARK: Writes

    /// Writes every part of a turn in one transaction: all of it or none of it.
    public func apply(_ turn: AppliedTurn) throws {
        let date = turn.newDate.iso
        try dbQueue.write { db in
            var balance = try Self.balance(db)
            for e in turn.ledger {
                balance += e.amountMinor
                try db.execute(sql: """
                    INSERT INTO ledger (date, source_type, amount_minor, reason, counterparty,
                                        balance_after_minor, origin)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [e.date.iso, e.sourceType.rawValue, e.amountMinor, e.reason,
                                     e.counterparty, balance, e.origin.rawValue])
            }

            for c in turn.streamChanges {
                switch c.action {
                case .start:
                    try db.execute(sql: """
                        INSERT INTO income_streams (name, kind, tier, monthly_minor, started_on)
                        VALUES (?, ?, ?, ?, ?)
                        """, arguments: [c.name, (c.kind ?? .wage).rawValue, c.tier, c.monthlyMinor ?? 0, date])
                case .change:
                    try db.execute(sql: """
                        UPDATE income_streams
                        SET tier = COALESCE(?, tier), monthly_minor = COALESCE(?, monthly_minor),
                            kind = COALESCE(?, kind)
                        WHERE name = ? AND ended_on IS NULL
                        """, arguments: [c.tier, c.monthlyMinor, c.kind?.rawValue, c.name])
                case .end:
                    try db.execute(sql: "UPDATE income_streams SET ended_on = ? WHERE name = ? AND ended_on IS NULL",
                                   arguments: [date, c.name])
                }
            }

            for d in turn.decisions {
                try db.execute(sql: "INSERT INTO decisions (date, summary, choice, importance) VALUES (?, ?, ?, ?)",
                               arguments: [date, d.summary, d.choice, d.importance.rawValue])
            }
            for s in turn.lifeState {
                try db.execute(sql: """
                    INSERT INTO life_state (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """, arguments: [s.key, s.value])
            }
            for u in turn.cast {
                if try Int64.fetchOne(db, sql: "SELECT id FROM cast_members WHERE name = ?", arguments: [u.name]) != nil {
                    try db.execute(sql: """
                        UPDATE cast_members
                        SET relation = COALESCE(?, relation), notes = COALESCE(?, notes),
                            status = COALESCE(?, status), last_seen = ?
                        WHERE name = ?
                        """, arguments: [u.relation, u.notes, u.status, date, u.name])
                } else {
                    try db.execute(sql: """
                        INSERT INTO cast_members (name, relation, notes, status, first_met, last_seen)
                        VALUES (?, ?, ?, COALESCE(?, 'alive'), ?, ?)
                        """, arguments: [u.name, u.relation, u.notes, u.status, date, date])
                }
            }
            for e in turn.events {
                try db.execute(sql: "INSERT INTO events (date, title, importance, uncanny) VALUES (?, ?, ?, ?)",
                               arguments: [date, e.title, e.importance.rawValue, e.uncanny])
            }

            try db.execute(sql: "INSERT INTO messages (role, text, date) VALUES (?, ?, ?)",
                           arguments: [ChatMessage.Role.player.rawValue, turn.playerText, date])
            try db.execute(sql: "INSERT INTO messages (role, text, date) VALUES (?, ?, ?)",
                           arguments: [ChatMessage.Role.narrator.rawValue, turn.narration, date])

            let rejections = String(decoding: try JSONEncoder().encode(turn.log.rejections), as: UTF8.self)
            try db.execute(sql: """
                INSERT INTO turn_log (date, fate, rejections_json, repaired, input_tokens, output_tokens)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [date, turn.log.fate, rejections, turn.log.repaired,
                                 turn.log.inputTokens, turn.log.outputTokens])

            try db.execute(sql: "UPDATE character SET game_date = ?", arguments: [date])
            try db.execute(sql: "UPDATE session SET last_played = ?",
                           arguments: [Date().timeIntervalSince1970])
        }
    }

    // MARK: Helpers

    private static func balance(_ db: Database) throws -> Int64 {
        try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM ledger") ?? 0
    }

    private static func parseDate(_ s: String) throws -> GameDate {
        guard let d = GameDate(iso: s) else { throw StoreError.corrupt("invalid date '\(s)'") }
        return d
    }
}
