import Foundation
import GRDB
import Testing
@testable import LifeCore

@Suite struct StoreTests {
    @Test func createdStoreStartsWithAgeAppropriateBalance() throws {
        let lib = try TestChat.library()
        let (id, store) = try TestChat.chat(lib, age: 30)
        #expect(try store.balanceMinor() == 175_000)
        let c = try store.character()
        #expect(c.name == "Lena"); #expect(c.id == id); #expect(c.ageYears == 30)
        #expect(c.currentDate == GameDate(year: 2020, month: 1, day: 1))
        #expect(try store.economy() == .sampleUS2005)
        let opening = try store.ledger(limit: 10)
        #expect(opening.count == 1); #expect(opening[0].sourceType == .opening)
        #expect(opening[0].balanceAfterMinor == 175_000)
    }

    @Test func createRefusesToOverwriteExistingFile() throws {
        let lib = try TestChat.library()
        let (id, _) = try TestChat.chat(lib)
        #expect(throws: StoreError.alreadyExists) {
            _ = try LifeStore.create(at: lib.fileURL(for: id), character: TestChat.newCharacter(),
                                     economy: .sampleUS2005)
        }
    }

    @Test func applyWritesEveryPart() throws {
        let lib = try TestChat.library()
        let (_, store) = try TestChat.chat(lib)
        let date = GameDate(year: 2020, month: 3, day: 1)
        try store.apply(TestChat.turn(
            playerText: "I take a job.", narration: "You start at the hardware store.", newDate: date,
            ledger: [NewLedgerEntry(date: date, sourceType: .wage, amountMinor: 200_000, reason: "pay",
                                    counterparty: nil, origin: .engine),
                     NewLedgerEntry(date: date, sourceType: .livingCost, amountMinor: -120_000,
                                    reason: "rent and food", counterparty: nil, origin: .engine)],
            streamChanges: [IncomeStreamChange(action: .start, name: "hardware store", kind: .wage,
                                               tier: "entry", monthlyMinor: 200_000)],
            decisions: [DecisionRecord(summary: "Took a job", choice: "hardware store", importance: .major)],
            lifeState: [LifeStateChange(key: "occupation", value: "clerk")],
            cast: [CastUpdate(name: "Maria", relation: "mother", notes: "worried", status: nil)],
            events: [EventRecord(title: "First day", importance: .minor, uncanny: false)],
            log: TurnLog(fate: 42, rejections: ["too much"], repaired: true, inputTokens: 10, outputTokens: 20)))

        #expect(try store.balanceMinor() == 175_000 + 200_000 - 120_000)
        let ledger = try store.ledger(limit: 10)
        #expect(ledger[0].balanceAfterMinor == 255_000); #expect(ledger[1].balanceAfterMinor == 375_000)
        #expect(try store.character().currentDate == date)
        let streams = try store.incomeStreams()
        #expect(streams.count == 1); #expect(streams[0].tier == "entry"); #expect(streams[0].startedOn == date)
        #expect(try store.decisions(limit: 5).map(\.summary) == ["Took a job"])
        #expect(try store.lifeState() == ["occupation": "clerk"])
        let cast = try store.castMembers()
        #expect(cast.count == 1); #expect(cast[0].name == "Maria"); #expect(cast[0].relation == "mother")
        let messages = try store.recentMessages(limit: 10)
        #expect(messages.map(\.role) == [.player, .narrator])
        #expect(messages.map(\.text) == ["I take a job.", "You start at the hardware store."])
        #expect(try store.turnLogs() == [TurnLog(fate: 42, rejections: ["too much"], repaired: true,
                                                 inputTokens: 10, outputTokens: 20)])
    }

    @Test func streamsCanChangeAndEnd() throws {
        let lib = try TestChat.library()
        let (_, store) = try TestChat.chat(lib)
        let start = IncomeStreamChange(action: .start, name: "shop", kind: .wage, tier: "entry", monthlyMinor: 200_000)
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 2, day: 1), streamChanges: [start]))
        let raise = IncomeStreamChange(action: .change, name: "shop", kind: nil, tier: "skilled", monthlyMinor: 300_000)
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 6, day: 1), streamChanges: [raise]))
        var s = try store.incomeStreams()
        #expect(s.count == 2)
        #expect(s[0].monthlyMinor == 200_000); #expect(s[0].tier == "entry")
        #expect(s[0].endedOn == GameDate(year: 2020, month: 6, day: 1))
        #expect(s[1].monthlyMinor == 300_000); #expect(s[1].tier == "skilled")
        #expect(s[1].endedOn == nil)
        let quit = IncomeStreamChange(action: .end, name: "shop", kind: nil, tier: nil, monthlyMinor: nil)
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 9, day: 1), streamChanges: [quit]))
        s = try store.incomeStreams()
        #expect(s[1].endedOn == GameDate(year: 2020, month: 9, day: 1))
    }

    @Test func castUpdatesUpsertCaseInsensitively() throws {
        let lib = try TestChat.library()
        let (_, store) = try TestChat.chat(lib)
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 1, day: 5),
                                      cast: [CastUpdate(name: "Maria", relation: "mother", notes: "kind", status: nil)]))
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 2, day: 5),
                                      cast: [CastUpdate(name: "MARIA", relation: nil, notes: "ill", status: "sick")]))
        let cast = try store.castMembers()
        #expect(cast.count == 1)
        #expect(cast[0].relation == "mother"); #expect(cast[0].notes == "ill"); #expect(cast[0].status == "sick")
        #expect(cast[0].firstMet == GameDate(year: 2020, month: 1, day: 5))
        #expect(cast[0].lastSeen == GameDate(year: 2020, month: 2, day: 5))
    }

    @Test func lastDatesForGiftsAndSources() throws {
        let lib = try TestChat.library()
        let (_, store) = try TestChat.chat(lib)
        let d1 = GameDate(year: 2020, month: 1, day: 10), d2 = GameDate(year: 2020, month: 4, day: 10)
        try store.apply(TestChat.turn(newDate: d1, ledger: [TestChat.gift(5_000, from: "Maria", on: d1)]))
        try store.apply(TestChat.turn(newDate: d2, ledger: [TestChat.gift(9_000, from: "maria", on: d2, source: .inheritance)]))
        #expect(try store.lastGiftDate(from: "MARIA") == d2)
        #expect(try store.lastGiftDate(from: "Joe") == nil)
        #expect(try store.lastLedgerDate(source: .gift) == d1)
        #expect(try store.lastLedgerDate(source: .windfall) == nil)
    }

    @Test func seedingAddsHistoryWithoutTranscriptOrTurnLog() throws {
        let lib = try TestChat.library()
        let (_, store) = try TestChat.chat(lib)
        try store.seedHistory(
            cast: [CastUpdate(name: "Maria", relation: "mother", notes: "kind", status: nil)],
            decisions: [DecisionRecord(summary: "Left her job", choice: "quit", importance: .major)],
            lifeState: [LifeStateChange(key: "residence", value: "a rented room")])
        #expect(try store.castMembers().map(\.name) == ["Maria"])
        #expect(try store.castMembers()[0].firstMet == GameDate(year: 2020, month: 1, day: 1))
        #expect(try store.decisions(limit: 5).map(\.summary) == ["Left her job"])
        #expect(try store.lifeState() == ["residence": "a rented room"])
        #expect(try store.recentMessages(limit: 5).isEmpty); #expect(try store.turnLogs().isEmpty)
        #expect(try store.balanceMinor() == 175_000)
    }

    @Test func twoChatsShareNothing() throws {
        let lib = try TestChat.library()
        let (_, a) = try TestChat.chat(lib, name: "Ana")
        let (_, b) = try TestChat.chat(lib, name: "Ben")
        let startB = try b.balanceMinor()
        try a.apply(TestChat.turn(ledger: [TestChat.gift(50_000, from: "Maria")],
                                  cast: [CastUpdate(name: "Maria", relation: "mother", notes: nil, status: nil)]))
        #expect(try a.balanceMinor() == 225_000)
        #expect(try b.balanceMinor() == startB)
        #expect(try b.castMembers().isEmpty)
        #expect(try b.recentMessages(limit: 10).isEmpty)
    }

    @Test func deleteRemovesFileAndSidecars() throws {
        let lib = try TestChat.library()
        let (id, _) = try TestChat.chat(lib)
        let file = lib.fileURL(for: id)
        for suffix in ["-wal", "-shm", "-journal"] {
            FileManager.default.createFile(atPath: file.path + suffix, contents: Data())
        }
        try lib.deleteChat(id: id)
        for suffix in ["", "-wal", "-shm", "-journal"] {
            #expect(!FileManager.default.fileExists(atPath: file.path + suffix))
        }
        #expect(try lib.list().isEmpty)
    }

    @Test func listShowsNameDateAgeNewestPlayedFirst() throws {
        let lib = try TestChat.library()
        let (idA, a) = try TestChat.chat(lib, name: "Ana", age: 30)
        Thread.sleep(forTimeInterval: 0.02)
        let (idB, _) = try TestChat.chat(lib, name: "Ben", age: 12)
        Thread.sleep(forTimeInterval: 0.02)
        try a.apply(TestChat.turn(newDate: GameDate(year: 2021, month: 1, day: 1)))
        let list = try lib.list()
        #expect(list.map(\.id) == [idA, idB])
        #expect(list[0].characterName == "Ana"); #expect(list[0].ageYears == 31)
        #expect(list[0].currentDate == GameDate(year: 2021, month: 1, day: 1))
        #expect(list[1].characterName == "Ben"); #expect(list[1].ageYears == 12)
    }

    @Test func listSkipsUnreadableChats() throws {
        let lib = try TestChat.library()
        let (id, _) = try TestChat.chat(lib)
        try Data("not a database".utf8).write(to: lib.directory.appendingPathComponent("\(UUID().uuidString).lifechat"))
        #expect(try lib.list().map(\.id) == [id])
    }

    @Test func applyIsAtomic() throws {
        let lib = try TestChat.library()
        let (_, store) = try TestChat.chat(lib)
        let before = try store.balanceMinor()
        let bad = TestChat.turn(ledger: [TestChat.gift(10_000, from: "Maria")],
                                cast: [CastUpdate(name: "", relation: nil, notes: nil, status: nil)])
        #expect(throws: (any Error).self) { try store.apply(bad) }
        #expect(try store.balanceMinor() == before)
        #expect(try store.ledger(limit: 10).count == 1)
        #expect(try store.recentMessages(limit: 10).isEmpty)
    }

    @Test func openingGarbageFileThrowsNotAStore() throws {
        let lib = try TestChat.library()
        let url = lib.directory.appendingPathComponent("junk.lifechat")
        try Data((0..<2048).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        #expect(throws: StoreError.notAStore) { _ = try LifeStore.open(at: url) }
    }

    @Test func openingFutureSchemaThrowsUnsupportedSchema() throws {
        let lib = try TestChat.library()
        let (id, _) = try TestChat.chat(lib)
        let url = lib.fileURL(for: id)
        let raw = try DatabaseQueue(path: url.path)
        try raw.write { try $0.execute(sql: "PRAGMA user_version = 99") }
        #expect(throws: StoreError.unsupportedSchema(found: 99)) { _ = try LifeStore.open(at: url) }
    }

    @Test func reopeningReadsPersistedState() throws {
        let lib = try TestChat.library()
        let (id, store) = try TestChat.chat(lib)
        try store.apply(TestChat.turn(ledger: [TestChat.gift(1_000, from: "Maria")]))
        let reopened = try lib.openChat(id: id)
        #expect(try reopened.balanceMinor() == 176_000)
        #expect(try reopened.character().name == "Lena")
    }
}
