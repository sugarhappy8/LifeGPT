import Foundation
import GRDB
import Testing
@testable import LifeCore

@Suite struct BankStoreTests {
    private let savings = AccountOpening(id: "savings", name: "Rainy day", kind: .savings)
    private let business = AccountOpening(id: "business", name: "Workshop", kind: .business)

    private func transfer(_ amount: Int64, from: String = "personal", to: String = "savings") -> [NewLedgerEntry] {
        [NewLedgerEntry(date: TestChat.date, sourceType: .transfer, amountMinor: -amount,
                        reason: "Set money aside", counterparty: to, origin: .engine, accountId: from),
         NewLedgerEntry(date: TestChat.date, sourceType: .transfer, amountMinor: amount,
                        reason: "Set money aside", counterparty: from, origin: .engine, accountId: to)]
    }

    @Test func freshStoreHasPersonalAccountFundedByOpeningLedger() throws {
        let store = try TestChat.chat(TestChat.library()).store
        #expect(try store.accounts() == [BankAccount(id: "personal", name: "Personal", kind: .personal,
                                                   balanceMinor: 175_000)])
        #expect(try store.ledger(limit: 10).map(\.accountId) == ["personal"])
    }

    @Test func accountsIncomeAndTransferDestinationsSurviveReopening() throws {
        let library = try TestChat.library()
        let (id, store) = try TestChat.chat(library)
        var turn = TestChat.turn(ledger: transfer(40_000), streamChanges: [
            .init(action: .start, name: "Repair shop", kind: .business, tier: nil, monthlyMinor: 15_000,
                  accountId: "business", pathId: "repair-shop"),
            .init(action: .start, name: "Garage rent", kind: .rental, tier: nil, monthlyMinor: 5_000,
                  accountId: "savings")])
        turn.accountOpenings = [savings, business]
        try store.apply(turn)
        let reopened = try library.openChat(id: id)
        #expect(try reopened.accounts() == [
            BankAccount(id: "personal", name: "Personal", kind: .personal, balanceMinor: 135_000),
            BankAccount(id: "savings", name: "Rainy day", kind: .savings, balanceMinor: 40_000),
            BankAccount(id: "business", name: "Workshop", kind: .business, balanceMinor: 0)])
        #expect(try reopened.balanceMinor() == 175_000)
        #expect(try reopened.ledger(limit: 2).map(\.accountId) == ["savings", "personal"])
        #expect(try reopened.ledger(limit: 2).map(\.balanceAfterMinor) == [175_000, 135_000])
        let streams = try reopened.incomeStreams()
        #expect(streams.map(\.accountId) == ["business", "savings"])
        #expect(streams.map(\.kind) == [.business, .rental])
        #expect(streams.first?.pathId == "repair-shop")
    }

    @Test func anAccountCannotSpendMoneyHeldInAnotherAccount() throws {
        let store = try TestChat.chat(TestChat.library()).store
        try store.applyFinancialChanges(accountOpenings: [savings], streamChanges: [], ledger: transfer(40_000),
                                        expectedRevision: 0)
        let before = try store.accounts()
        let entry = NewLedgerEntry(date: TestChat.date, sourceType: .expense, amountMinor: -50_000,
                                   reason: "Purchase", counterparty: nil, origin: .engine, accountId: "savings")
        #expect(throws: ValidationError.self) { try store.apply(TestChat.turn(ledger: [entry])) }
        #expect(try store.accounts() == before)
        #expect(try store.balanceMinor() == 175_000)
        #expect(try store.revision() == 1)
        #expect(try store.recentMessages(limit: 10).isEmpty)
    }

    @Test func unknownAccountAndUnbalancedTransfersRollBackOpeningsAndStory() throws {
        let store = try TestChat.chat(TestChat.library()).store
        let badEntries = [
            transfer(20_000, to: "missing"),
            Array(transfer(20_000).prefix(1)),
            transfer(200_000),
            transfer(0)]
        for entries in badEntries {
            var turn = TestChat.turn(ledger: entries)
            turn.accountOpenings = [savings]
            #expect(throws: ValidationError.self) { try store.apply(turn) }
            #expect(try store.accounts().count == 1)
            #expect(try store.balanceMinor() == 175_000)
            #expect(try store.ledger(limit: 20).count == 1)
            #expect(try store.revision() == 0)
            #expect(try store.turnLogs().isEmpty)
            #expect(try store.recentMessages(limit: 10).isEmpty)
        }
    }

    @Test func duplicateOrBlankAccountsAreRejectedAtomically() throws {
        let store = try TestChat.chat(TestChat.library()).store
        for invalid in [AccountOpening(id: "another", name: "personal", kind: .business),
                        AccountOpening(id: "personal", name: "Another name", kind: .savings),
                        AccountOpening(id: " ", name: "Blank ID", kind: .savings),
                        AccountOpening(id: "empty-name", name: " \n ", kind: .savings), savings] {
            var turn = TestChat.turn()
            turn.accountOpenings = [savings, invalid]
            #expect(throws: ValidationError.self) { try store.apply(turn) }
            #expect(try store.accounts().map(\.id) == ["personal"])
            #expect(try store.revision() == 0)
        }
    }

    @Test func overflowRejectsTheEntireFinancialWrite() throws {
        let store = try TestChat.chat(TestChat.library()).store
        let overflow = NewLedgerEntry(date: TestChat.date, sourceType: .gift, amountMinor: Int64.max,
                                      reason: "Too much", counterparty: nil, origin: .engine, accountId: "savings")
        #expect(throws: ValidationError.self) {
            try store.applyFinancialChanges(accountOpenings: [savings], streamChanges: [], ledger: [overflow],
                                            expectedRevision: 0)
        }
        #expect(try store.accounts().count == 1)
        #expect(try store.ledger(limit: 10).count == 1)
        #expect(try store.revision() == 0)
    }

    @Test func manualFinancialChangesKeepStoryAndDateIntactAndRejectStaleRevision() throws {
        let store = try TestChat.chat(TestChat.library()).store
        let income = IncomeStreamChange(action: .start, name: "Weekly allowance", kind: .allowance,
                                         tier: nil, monthlyMinor: 5_000, accountId: "savings")
        try store.applyFinancialChanges(accountOpenings: [savings], streamChanges: [income], ledger: transfer(25_000),
                                        expectedRevision: 0)
        #expect(try store.revision() == 1)
        #expect(try store.character().currentDate == TestChat.date)
        #expect(try store.recentMessages(limit: 10).isEmpty)
        #expect(try store.turnLogs().isEmpty)
        #expect(try store.incomeStreams().first?.startedOn == TestChat.date)
        #expect(try store.dbQueue.read { try String.fetchAll($0, sql: "SELECT title FROM events") }
                == ["Financial records updated"])
        #expect(throws: ValidationError.self) {
            try store.applyFinancialChanges(accountOpenings: [business], streamChanges: [], ledger: [],
                                            expectedRevision: 0)
        }
        var staleTurn = TestChat.turn()
        staleTurn.accountOpenings = [business]
        staleTurn.expectedRevision = 0
        #expect(throws: ValidationError.self) { try store.apply(staleTurn) }
        #expect(try store.accounts().map(\.id) == ["personal", "savings"])
        #expect(try store.revision() == 1)
        #expect(try store.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM events") } == 1)
    }

    @Test func changesPreserveIncomeVersionsAndUseTheirEffectiveDates() throws {
        let library = try TestChat.library()
        let (id, store) = try TestChat.chat(library)
        var start = TestChat.turn(newDate: GameDate(year: 2020, month: 4, day: 1), streamChanges: [
            .init(action: .start, name: "Repair shop", kind: .business, tier: nil, monthlyMinor: 10_000,
                  pathId: "repair-shop", effectiveFrom: "2020-02-01")])
        start.accountOpenings = [business]
        try store.apply(start)
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 6, day: 1), streamChanges: [
            .init(action: .change, name: "REPAIR SHOP", kind: nil, tier: nil, monthlyMinor: 20_000,
                  accountId: "business", effectiveFrom: "2020-05-01")]))
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 8, day: 1), streamChanges: [
            .init(action: .end, name: "repair shop", kind: nil, tier: nil, monthlyMinor: nil,
                  effectiveFrom: "2020-07-01")]))
        let streams = try library.openChat(id: id).incomeStreams()
        #expect(streams.count == 2)
        #expect(streams.map(\.name) == ["Repair shop", "Repair shop"])
        #expect(streams.map(\.monthlyMinor) == [10_000, 20_000])
        #expect(streams.map(\.accountId) == ["personal", "business"])
        #expect(streams.map(\.pathId) == ["repair-shop", "repair-shop"])
        #expect(streams.map { $0.startedOn.iso } == ["2020-02-01", "2020-05-01"])
        #expect(streams.map { $0.endedOn?.iso } == ["2020-05-01", "2020-07-01"])
    }

    @Test func invalidIncomeRollsBackAllFinancialAndStoryChanges() throws {
        let store = try TestChat.chat(TestChat.library()).store
        let invalidChanges: [[IncomeStreamChange]] = [
            [.init(action: .start, name: "Job", kind: .wage, tier: nil, monthlyMinor: 0)],
            [.init(action: .start, name: "Job", kind: .wage, tier: nil, monthlyMinor: nil)],
            [.init(action: .start, name: " ", kind: .wage, tier: nil, monthlyMinor: 100)],
            [.init(action: .start, name: "Job", kind: .wage, tier: nil, monthlyMinor: 100, accountId: "missing")],
            [.init(action: .start, name: "Job", kind: .wage, tier: nil, monthlyMinor: 100, effectiveFrom: "2019-12-31")],
            [.init(action: .start, name: "Job", kind: .wage, tier: nil, monthlyMinor: 100, effectiveFrom: "2020-01-02")],
            [.init(action: .start, name: "Job", kind: .wage, tier: nil, monthlyMinor: 100, effectiveFrom: "not-a-date")],
            [.init(action: .change, name: "Missing", kind: nil, tier: nil, monthlyMinor: 100)],
            [.init(action: .end, name: "Missing", kind: nil, tier: nil, monthlyMinor: nil)],
            [.init(action: .start, name: "Job", kind: .wage, tier: nil, monthlyMinor: 100),
             .init(action: .start, name: "JOB", kind: .wage, tier: nil, monthlyMinor: 200)]]
        for changes in invalidChanges {
            var turn = TestChat.turn(ledger: transfer(20_000), streamChanges: changes)
            turn.accountOpenings = [savings]
            #expect(throws: ValidationError.self) { try store.apply(turn) }
            #expect(try store.incomeStreams().isEmpty)
            #expect(try store.accounts().count == 1)
            #expect(try store.balanceMinor() == 175_000)
            #expect(try store.ledger(limit: 10).count == 1)
            #expect(try store.recentMessages(limit: 10).isEmpty)
            #expect(try store.revision() == 0)
        }
    }

    @Test func legacyIncomeJSONDecodesWithPersonalAccountDefaults() throws {
        let legacy = Data(#"{"name":"Shop","kind":"wage","monthlyMinor":100,"startedOn":{"year":2020,"month":1,"day":1}}"#.utf8)
        let stream = try JSONDecoder().decode(IncomeStream.self, from: legacy)
        #expect(stream.accountId == "personal")
        #expect(stream.pathId == nil)
        #expect(try JSONDecoder().decode(IncomeStream.self, from: JSONEncoder().encode(stream)) == stream)
        let changeJSON = Data(#"{"action":"start","name":"Shop","kind":"wage","monthlyMinor":100}"#.utf8)
        let change = try JSONDecoder().decode(IncomeStreamChange.self, from: changeJSON)
        #expect(change.accountId == nil)
        #expect(change.pathId == nil)
        #expect(change.effectiveFrom == nil)
        #expect(change.reason == nil)
    }

    @Test func changingBusinessIncomeKindClearsOnlyTheNewVersionsPath() throws {
        let store = try TestChat.chat(TestChat.library()).store
        try store.apply(TestChat.turn(streamChanges: [
            .init(action: .start, name: "Shop", kind: .business, tier: nil, monthlyMinor: 100,
                  pathId: "shop")]))
        try store.apply(TestChat.turn(streamChanges: [
            .init(action: .change, name: "Shop", kind: .selfEmployment, tier: nil, monthlyMinor: nil)]))
        let streams = try store.incomeStreams()
        #expect(streams.map(\.kind) == [.business, .selfEmployment])
        #expect(streams.map(\.pathId) == ["shop", nil])
    }

    @Test func sameTurnRestartCannotOverlapTheEndedVersion() throws {
        let store = try TestChat.chat(TestChat.library()).store
        let changes: [IncomeStreamChange] = [
            .init(action: .start, name: "Shop", kind: .wage, tier: nil, monthlyMinor: 100,
                  effectiveFrom: "2020-01-01"),
            .init(action: .end, name: "Shop", kind: nil, tier: nil, monthlyMinor: nil,
                  effectiveFrom: "2020-03-01"),
            .init(action: .start, name: "Shop", kind: .wage, tier: nil, monthlyMinor: 200,
                  effectiveFrom: "2020-02-01")]
        #expect(throws: ValidationError.self) {
            try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 4, day: 1), streamChanges: changes))
        }
        #expect(try store.incomeStreams().isEmpty)
        #expect(try store.character().currentDate == TestChat.date)
    }

    @Test func v2MigrationAssignsAllExistingMoneyAndIncomeToPersonal() throws {
        let library = try TestChat.library()
        let url = library.fileURL(for: UUID())
        let queue = try DatabaseQueue(path: url.path)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schema = try String(contentsOf: root.appendingPathComponent("Fixtures/stores/v1-schema.sql"), encoding: .utf8)
        try queue.write { db in
            try db.execute(sql: schema)
            try db.execute(sql: """
                ALTER TABLE session ADD COLUMN settings_json TEXT NOT NULL DEFAULT '{}';
                ALTER TABLE session ADD COLUMN author_notes TEXT NOT NULL DEFAULT '';
                ALTER TABLE session ADD COLUMN choices_json TEXT NOT NULL DEFAULT '[]';
                ALTER TABLE session ADD COLUMN ended INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE session ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;
                CREATE TABLE place_time_brief (version INTEGER PRIMARY KEY, date TEXT NOT NULL, location TEXT NOT NULL, text TEXT NOT NULL);
                CREATE TABLE life_state_history (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL);
                CREATE TABLE opportunity_paths (id TEXT PRIMARY KEY, json TEXT NOT NULL);
                CREATE TABLE story_threads (id TEXT PRIMARY KEY, json TEXT NOT NULL);
                CREATE TABLE chapter_summaries (id INTEGER PRIMARY KEY AUTOINCREMENT, through_message_id INTEGER NOT NULL UNIQUE, date TEXT NOT NULL, text TEXT NOT NULL);
                CREATE TABLE financial_positions (id TEXT PRIMARY KEY, json TEXT NOT NULL);
                CREATE INDEX messages_date ON messages(date);
                CREATE INDEX decisions_date ON decisions(date);
                INSERT INTO grdb_migrations VALUES ('v2');
                PRAGMA user_version = 2;
                """)
            let id = UUID().uuidString
            try db.execute(sql: "INSERT INTO session (id, schema_version, created_at, last_played, swing_dial, reply_length_words) VALUES (?, 2, 0, 0, 1, 200)", arguments: [id])
            try db.execute(sql: "INSERT INTO character VALUES (?, 'Legacy', 'Ohio', 1990, 'Tall', 30, NULL, 'middle', '1990-01-01', '2020-01-01')", arguments: [id])
            try db.execute(sql: "INSERT INTO economy_card VALUES (1, ?)", arguments: [LifeStore.json(EconomyCard.sampleUS2005)])
            try db.execute(sql: """
                INSERT INTO ledger (date, source_type, amount_minor, reason, balance_after_minor, origin)
                VALUES ('2020-01-01', 'opening', 175000, 'Starting savings', 175000, 'engine'),
                       ('2020-01-01', 'expense', -5000, 'Groceries', 170000, 'engine');
                INSERT INTO income_streams (name, kind, tier, monthly_minor, started_on, ended_on)
                VALUES ('Old job', 'wage', 'entry', 200000, '2018-01-01', '2019-01-01'),
                       ('Shop', 'self_employment', NULL, 100000, '2019-01-01', NULL);
                INSERT INTO messages (role, text, date) VALUES ('narrator', 'An existing life.', '2020-01-01');
                """)
        }
        let store = try LifeStore.open(at: url)
        #expect(try store.accounts() == [BankAccount(id: "personal", name: "Personal", kind: .personal,
                                                   balanceMinor: 170_000)])
        #expect(try store.balanceMinor() == 170_000)
        #expect(try store.ledger(limit: 10).map(\.amountMinor) == [-5_000, 175_000])
        #expect(try store.ledger(limit: 10).map(\.balanceAfterMinor) == [170_000, 175_000])
        #expect(try store.ledger(limit: 10).map(\.accountId) == ["personal", "personal"])
        #expect(try store.incomeStreams().map(\.accountId) == ["personal", "personal"])
        #expect(try store.incomeStreams().map(\.monthlyMinor) == [200_000, 100_000])
        #expect(try store.incomeStreams().first?.endedOn?.iso == "2019-01-01")
        #expect(try store.recentMessages(limit: 10).first?.text == "An existing life.")
        #expect(try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == Schema.version)
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT schema_version FROM session") } == Schema.version)
        #expect(try LifeStore.open(at: url).accounts() == store.accounts())
    }
}
