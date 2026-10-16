import Foundation
import GRDB

/// One chat's database: a single SQLite file holding the character, ledger,
/// cast, decisions, and transcript. Nothing in it is shared with another chat.
public final class LifeStore: Sendable {
    public let url: URL
    let dbQueue: DatabaseQueue

    private init(url: URL, dbQueue: DatabaseQueue) {
        self.url = url
        self.dbQueue = dbQueue
    }

    // MARK: Create and open

    public static func create(at url: URL, character: NewCharacter, economy: EconomyCard,
                              id: UUID = UUID()) throws -> LifeStore {
        try character.validate()
        try economy.validate()
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
        if version > Schema.version { throw StoreError.unsupportedSchema(found: version) }
        try Schema.migrate(queue)
        let valid = try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM character") == 1 }
        guard valid else { throw StoreError.notAStore }
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
            try new.validate()
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
            let card = try JSONDecoder().decode(EconomyCard.self, from: Data(json.utf8))
            try card.validate()
            return card
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

    /// The personal account comes first; other accounts retain their opening order.
    public func accounts() throws -> [BankAccount] {
        try dbQueue.read { db in
            let balances = try Self.accountBalances(db)
            return try Row.fetchAll(db, sql: "SELECT * FROM accounts ORDER BY id != 'personal', rowid").map { row in
                let id: String = row["id"]
                guard let kind = BankAccount.Kind(rawValue: row["kind"]) else {
                    throw StoreError.corrupt("invalid account kind")
                }
                return BankAccount(id: id, name: row["name"], kind: kind, balanceMinor: balances[id] ?? 0)
            }
        }
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
                            balanceAfterMinor: row["balance_after_minor"], accountId: row["account_id"])
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
                             endedOn: try (row["ended_on"] as String?).map(Self.parseDate),
                             accountId: row["account_id"], pathId: row["path_id"])
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
            if let expected = turn.expectedRevision {
                let current = try Int.fetchOne(db, sql: "SELECT revision FROM session") ?? 0
                guard current == expected else { throw ValidationError.invalid("This life changed during the reply. Please try again.") }
            }
            try Self.writeFinances(db, accountOpenings: turn.accountOpenings, streamChanges: turn.streamChanges,
                                   ledger: turn.ledger, through: turn.newDate)

            try Self.writeStory(db, date: date, decisions: turn.decisions, lifeState: turn.lifeState, cast: turn.cast)
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

            try Self.writeTurnMemory(db, turn: turn)
            try db.execute(sql: "UPDATE character SET game_date = ?", arguments: [date])
            try db.execute(sql: "UPDATE session SET revision = revision + 1")
            try db.execute(sql: "UPDATE session SET last_played = ?",
                           arguments: [Date().timeIntervalSince1970])
        }
    }

    /// Records deliberate financial edits at the current date, without advancing the story.
    public func applyFinancialChanges(accountOpenings: [AccountOpening], streamChanges: [IncomeStreamChange],
                                      ledger: [NewLedgerEntry], expectedRevision: Int) throws {
        try dbQueue.write { db in
            let current = try Int.fetchOne(db, sql: "SELECT revision FROM session") ?? 0
            guard current == expectedRevision else {
                throw ValidationError.invalid("This life changed during the edit. Please try again.")
            }
            let date = try Self.parseDate(String.fetchOne(db, sql: "SELECT game_date FROM character") ?? "")
            try Self.writeFinances(db, accountOpenings: accountOpenings, streamChanges: streamChanges,
                                   ledger: ledger, through: date)
            try db.execute(sql: "INSERT INTO events (date, title, importance, uncanny) VALUES (?, ?, 'minor', 0)",
                           arguments: [date.iso, "Financial records updated"])
            try db.execute(sql: "UPDATE session SET revision = revision + 1, last_played = ?",
                           arguments: [Date().timeIntervalSince1970])
        }
    }

    /// Adds starting history (people, decisions, life state) to a fresh chat
    /// without touching the transcript, turn log, or ledger.
    public func seedHistory(cast: [CastUpdate], decisions: [DecisionRecord], lifeState: [LifeStateChange]) throws {
        try dbQueue.write { db in
            let date = try String.fetchOne(db, sql: "SELECT game_date FROM character") ?? ""
            try Self.writeStory(db, date: date, decisions: decisions, lifeState: lifeState, cast: cast)
        }
    }

    // MARK: Helpers

    private static func writeFinances(_ db: Database, accountOpenings: [AccountOpening],
                                      streamChanges: [IncomeStreamChange], ledger: [NewLedgerEntry],
                                      through newDate: GameDate) throws {
        try Self.openAccounts(db, openings: accountOpenings)
        var balances = try Self.accountBalances(db)
        var balance = try Self.balance(db)
        let transferTotal = try ledger.filter { $0.sourceType == .transfer }.reduce(Int64(0)) {
            guard $1.amountMinor != 0 else { throw ValidationError.invalid("A transfer must move a positive amount.") }
            return try CheckedMoney.add($0, $1.amountMinor)
        }
        guard transferTotal == 0 else { throw ValidationError.invalid("Transfer debits and credits must balance.") }
        for e in ledger {
            guard let accountBalance = balances[e.accountId] else {
                throw ValidationError.invalid("The ledger refers to an unknown account: \(e.accountId).")
            }
            let nextAccountBalance = try CheckedMoney.add(accountBalance, e.amountMinor)
            guard nextAccountBalance >= 0 else {
                throw ValidationError.invalid("The \(e.accountId) account does not have enough money.")
            }
            balances[e.accountId] = nextAccountBalance
            balance = try CheckedMoney.add(balance, e.amountMinor)
            try db.execute(sql: """
                INSERT INTO ledger (date, source_type, amount_minor, reason, counterparty,
                                    balance_after_minor, origin, account_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [e.date.iso, e.sourceType.rawValue, e.amountMinor, e.reason,
                                 e.counterparty, balance, e.origin.rawValue, e.accountId])
        }

        try Self.writeIncomeChanges(db, changes: streamChanges, through: newDate,
                                    accountIDs: Set(balances.keys))
    }

    private static func openAccounts(_ db: Database, openings: [AccountOpening]) throws {
        for opening in openings {
            guard !opening.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !opening.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalid("Accounts need an ID and a name.")
            }
            let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM accounts WHERE id = ? OR name = ?)",
                                           arguments: [opening.id, opening.name]) ?? false
            guard !exists else { throw ValidationError.invalid("That account ID or name already exists.") }
            try db.execute(sql: "INSERT INTO accounts (id, name, kind) VALUES (?, ?, ?)",
                           arguments: [opening.id, opening.name, opening.kind.rawValue])
        }
    }

    private static func writeIncomeChanges(_ db: Database, changes: [IncomeStreamChange],
                                           through newDate: GameDate, accountIDs: Set<String>) throws {
        guard !changes.isEmpty else { return }
        let currentDate = try parseDate(String.fetchOne(db, sql: "SELECT game_date FROM character") ?? "")
        for change in changes {
            guard !change.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalid("Income streams need a name.")
            }
            guard let effective = GameDate(iso: change.effectiveFrom ?? newDate.iso),
                  effective >= currentDate, effective <= newDate else {
                throw ValidationError.invalid("Income changes must take effect within the current turn.")
            }
            if let amount = change.monthlyMinor, amount <= 0 {
                throw ValidationError.invalid("Recurring income must have a positive monthly amount.")
            }
            if let accountID = change.accountId, !accountIDs.contains(accountID) {
                throw ValidationError.invalid("Income refers to an unknown account: \(accountID).")
            }
            if let pathID = change.pathId, pathID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.invalid("An income path ID cannot be empty.")
            }
            let active = try Row.fetchAll(db, sql: "SELECT * FROM income_streams WHERE name = ? AND ended_on IS NULL",
                                          arguments: [change.name])
            switch change.action {
            case .start:
                guard active.isEmpty else { throw ValidationError.invalid("An active income stream already has that name.") }
                if let lastEnd = try String.fetchOne(db, sql: "SELECT MAX(ended_on) FROM income_streams WHERE name = ?",
                                                    arguments: [change.name]),
                   try parseDate(lastEnd) > effective {
                    throw ValidationError.invalid("Income versions with the same name cannot overlap.")
                }
                guard let amount = change.monthlyMinor, amount > 0 else {
                    throw ValidationError.invalid("Recurring income must have a positive monthly amount.")
                }
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM income_streams WHERE ended_on IS NULL") ?? 0
                guard count < 20 else { throw ValidationError.invalid("A life can have at most 20 active income streams.") }
                let kind = change.kind ?? .wage
                guard change.pathId == nil || kind == .business else {
                    throw ValidationError.invalid("Only business income can link to a business path.")
                }
                try insertIncome(db, stream: IncomeStream(name: change.name, kind: kind,
                    tier: change.tier, monthlyMinor: amount, startedOn: effective,
                    accountId: change.accountId ?? "personal", pathId: change.pathId))
            case .change, .end:
                guard active.count == 1, let previous = active.first else {
                    throw ValidationError.invalid("Income changes require one matching active stream.")
                }
                guard effective >= (try parseDate(previous["started_on"])) else {
                    throw ValidationError.invalid("Income cannot change before its start date.")
                }
                try db.execute(sql: "UPDATE income_streams SET ended_on = ? WHERE id = ?",
                               arguments: [effective.iso, previous["id"] as Int64])
                if change.action == .change {
                    guard let previousKind = IncomeStream.Kind(rawValue: previous["kind"]) else {
                        throw StoreError.corrupt("invalid income kind")
                    }
                    let kind = change.kind ?? previousKind
                    guard change.pathId == nil || kind == .business else {
                        throw ValidationError.invalid("Only business income can link to a business path.")
                    }
                    let pathID: String? = kind == .business ? (change.pathId ?? previous["path_id"]) : nil
                    let replacement = IncomeStream(name: previous["name"], kind: kind,
                        tier: change.tier ?? previous["tier"],
                        monthlyMinor: change.monthlyMinor ?? previous["monthly_minor"], startedOn: effective,
                        accountId: change.accountId ?? previous["account_id"], pathId: pathID)
                    guard replacement.monthlyMinor > 0, accountIDs.contains(replacement.accountId) else {
                        throw ValidationError.invalid("Recurring income needs a positive amount and an existing account.")
                    }
                    try insertIncome(db, stream: replacement)
                }
            }
        }
    }

    private static func insertIncome(_ db: Database, stream: IncomeStream) throws {
        try db.execute(sql: """
            INSERT INTO income_streams (name, kind, tier, monthly_minor, started_on, account_id, path_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [stream.name, stream.kind.rawValue, stream.tier, stream.monthlyMinor,
                             stream.startedOn.iso, stream.accountId, stream.pathId])
    }

    /// Decisions, life state and cast changes, shared by `apply` and `seedHistory`.
    private static func writeStory(_ db: Database, date: String, decisions: [DecisionRecord],
                                   lifeState: [LifeStateChange], cast: [CastUpdate]) throws {
        for d in decisions {
            try db.execute(sql: "INSERT INTO decisions (date, summary, choice, importance) VALUES (?, ?, ?, ?)",
                           arguments: [date, d.summary, d.choice, d.importance.rawValue])
        }
        for s in lifeState {
            try db.execute(sql: "INSERT INTO life_state_history (date, key, value) VALUES (?, ?, ?)", arguments: [date, s.key, s.value])
            try db.execute(sql: """
                INSERT INTO life_state (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [s.key, s.value])
        }
        for u in cast {
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
    }

    private static func balance(_ db: Database) throws -> Int64 {
        try Int64.fetchAll(db, sql: "SELECT amount_minor FROM ledger ORDER BY id")
            .reduce(Int64(0)) { try CheckedMoney.add($0, $1) }
    }

    private static func accountBalances(_ db: Database) throws -> [String: Int64] {
        var balances = Dictionary(uniqueKeysWithValues: try String.fetchAll(db, sql: "SELECT id FROM accounts")
            .map { ($0, Int64(0)) })
        for row in try Row.fetchAll(db, sql: "SELECT account_id, amount_minor FROM ledger ORDER BY id") {
            let accountID: String = row["account_id"]
            guard let balance = balances[accountID] else { throw StoreError.corrupt("ledger account does not exist") }
            balances[accountID] = try CheckedMoney.add(balance, row["amount_minor"])
        }
        return balances
    }

    static func parseDate(_ s: String) throws -> GameDate {
        guard let d = GameDate(iso: s) else { throw StoreError.corrupt("invalid date '\(s)'") }
        return d
    }
}
