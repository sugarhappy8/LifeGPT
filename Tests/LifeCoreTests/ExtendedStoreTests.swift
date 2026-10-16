import Foundation
import GRDB
import Testing
@testable import LifeCore

@Suite struct ExtendedStoreTests {
    @Test func setupSettingsMemoryAndEconomySurviveReopening() throws {
        let library = try TestChat.library()
        var setup = SetupDraft.manual(for: TestChat.newCharacter())
        setup.placeBrief = "A small town in 2020."
        setup.cast = [CastUpdate(name: "Nora", relation: "sister", notes: "Works nearby", status: "alive")]
        var settings = SessionSettings(); settings.voiceBible = "Plain sentences, close observation."
        let (id, store) = try library.createChat(character: TestChat.newCharacter(), setup: setup, settings: settings)
        let reopened = try library.openChat(id: id)
        #expect(try reopened.sessionSettings() == settings)
        #expect(try reopened.placeTimeBriefs().last?.text == setup.placeBrief)
        #expect(try reopened.choices() == setup.choices)
        #expect(try reopened.recentMessages(limit: 5).count == 1)
        #expect(try reopened.balanceMinor() == StartingMoney.balanceMinor(forAge: 30, economy: setup.economy))
        #expect(try store.castMembers().first?.name == "Nora")
    }

    @Test func invalidSetupDoesNotLeaveASave() throws {
        let library = try TestChat.library()
        var draft = SetupDraft.manual(for: TestChat.newCharacter()); draft.economy.medianMonthlyIncomeMinor = -1
        #expect(throws: ValidationError.self) { _ = try library.createChat(character: TestChat.newCharacter(), setup: draft, settings: SessionSettings()) }
        #expect(try library.list().isEmpty)
    }

    @Test func revisionRejectsStaleTurnAtomically() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        var turn = TestChat.turn(ledger: [TestChat.gift(100, from: "Maria")]); turn.expectedRevision = try store.revision()
        try store.updateSettings(SessionSettings(), swingDial: 0, replyLengthWords: 200)
        #expect(throws: ValidationError.self) { try store.apply(turn) }
        #expect(try store.recentMessages(limit: 10).isEmpty)
        #expect(try store.ledger(limit: 100).count == 1)
    }

    @Test func backupIncludesCommittedWALAndImportGetsSeparateIdentity() throws {
        let library = try TestChat.library()
        let original = try TestChat.chat(library)
        try original.store.apply(TestChat.turn(narration: "The story continues.", ledger: [TestChat.gift(123, from: "Nora")]))
        let destination = library.directory.appendingPathComponent("backup.lifechat")
        try original.store.backup(to: destination)
        let importedID = try library.importChat(from: destination)
        let imported = try library.openChat(id: importedID)
        #expect(try imported.character().id == importedID)
        #expect(importedID != original.id)
        #expect(try imported.balanceMinor() == original.store.balanceMinor())
        #expect(try imported.recentMessages(limit: 10).last?.text == "The story continues.")
        try library.deleteChat(id: importedID)
        #expect(try original.store.character().id == original.id)
    }

    @Test func worldVersionsPreserveHistoryAndPreventCurrencyReinterpretation() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        let original = try store.balanceMinor()
        var economy = try store.economy()
        try store.saveWorld(brief: PlaceTimeBrief(date: TestChat.date, location: "Ohio", text: "First setting"), economy: economy)
        economy.monthlyLivingCostMinor += 1000
        try store.saveWorld(brief: PlaceTimeBrief(date: TestChat.date, location: "New York", text: "A move"), economy: economy)
        #expect(try store.placeTimeBriefs().map(\.text) == ["First setting", "A move"])
        #expect(try store.economy().version == 3)
        #expect(try store.balanceMinor() == original)
        economy.currency = "JPY"; economy.minorUnitsPerUnit = 1
        #expect(throws: ValidationError.self) {
            try store.saveWorld(brief: PlaceTimeBrief(date: TestChat.date, location: "Tokyo", text: "A new home"), economy: economy)
        }
        #expect(try store.placeTimeBriefs().count == 2)
    }

    @Test func memoryCompactionRetainsTheCompleteTranscript() throws {
        let store = try TestChat.chat(try TestChat.library()).store
        for index in 0..<24 { try store.apply(TestChat.turn(playerText: "Attempt \(index)", narration: "Scene \(index)")) }
        try MemoryCompactor.compactIfNeeded(store: store)
        let chapter = try #require(store.chapters().first)
        #expect(chapter.text.contains("Scene 0"))
        #expect(chapter.throughMessageID == 24)
        #expect(try store.messageCount() == 48)
        try MemoryCompactor.compactIfNeeded(store: store)
        #expect(try store.chapters().count == 1)
    }

    @Test func invalidEconomiesAndCharacterYearsAreRejectedBeforeCreation() throws {
        let library = try TestChat.library()
        var character = TestChat.newCharacter(); character.birthYear = Int.max
        #expect(throws: ValidationError.self) { _ = try library.createChat(character: character, economy: .sampleUS2005) }
        var economy = EconomyCard.sampleUS2005; economy.medianMonthlyIncomeMinor = Int64.max
        #expect(throws: ValidationError.self) { _ = try library.createChat(character: TestChat.newCharacter(), economy: economy) }
        #expect(try library.list().isEmpty)
        #expect(GameDate(iso: "9223372036854775807-01-01") == nil)
    }
}

@Suite struct MigrationTests {
    @Test func v1SavesMigrateWithoutLosingMoneyOrTranscript() throws {
        let library = try TestChat.library()
        let id = UUID(), file = library.fileURL(for: UUID())
        let queue = try DatabaseQueue(path: file.path)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schema = try String(contentsOf: root.appendingPathComponent("Fixtures/stores/v1-schema.sql"), encoding: .utf8)
        try queue.write { db in
            try db.execute(sql: schema)
            try db.execute(sql: "INSERT INTO session VALUES (?, 1, 0, 0, 1, 200)", arguments: [id.uuidString])
            try db.execute(sql: "INSERT INTO character VALUES (?, 'Legacy', 'Ohio', 1990, 'Tall', 30, NULL, 'middle', '1990-01-01', '2020-01-01')", arguments: [id.uuidString])
            try db.execute(sql: "INSERT INTO economy_card VALUES (1, ?)", arguments: [LifeStore.json(EconomyCard.sampleUS2005)])
            try db.execute(sql: "INSERT INTO ledger (date, source_type, amount_minor, reason, balance_after_minor, origin) VALUES ('2020-01-01', 'opening', 175000, 'Starting savings', 175000, 'engine')")
            try db.execute(sql: "INSERT INTO messages (role, text, date) VALUES ('narrator', 'An older story.', '2020-01-01')")
        }
        let importedID = try library.importChat(from: file)
        #expect(try library.openChat(id: importedID).character().name == "Legacy")
        #expect(try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 1)
        let migrated = try LifeStore.open(at: file)
        #expect(try migrated.character().name == "Legacy")
        #expect(try migrated.balanceMinor() == 175_000)
        #expect(try migrated.recentMessages(limit: 2).first?.text == "An older story.")
        #expect(try migrated.sessionSettings() == SessionSettings())
        #expect(try migrated.paths().isEmpty)
        #expect(try migrated.revision() == 0)
        #expect(try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == Schema.version)
    }
}
