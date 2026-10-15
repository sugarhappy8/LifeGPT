import Foundation
@testable import LifeCore

/// Shared fixtures: temp chat libraries and a standard character.
enum TestChat {
    static func newCharacter(name: String = "Lena", age: Int = 30, birthYear: Int = 1990,
                             tier: WealthTier = .middle) -> NewCharacter {
        NewCharacter(name: name, birthplace: "Ohio, USA", birthYear: birthYear,
                     appearance: "tall, freckles", startingAge: age, background: nil,
                     familyWealthTier: tier)
    }

    static func library() throws -> ChatLibrary {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifegpt-tests-\(UUID().uuidString)")
        return try ChatLibrary(directory: dir)
    }

    static func chat(_ lib: ChatLibrary, name: String = "Lena", age: Int = 30)
        throws -> (id: UUID, store: LifeStore) {
        try lib.createChat(character: newCharacter(name: name, age: age), economy: .sampleUS2005)
    }

    static let date = GameDate(year: 2020, month: 1, day: 1)

    static func turn(playerText: String = "I look around.", narration: String = "You look around.",
                     newDate: GameDate = TestChat.date,
                     ledger: [NewLedgerEntry] = [], streamChanges: [IncomeStreamChange] = [],
                     decisions: [DecisionRecord] = [], lifeState: [LifeStateChange] = [],
                     cast: [CastUpdate] = [], events: [EventRecord] = [],
                     log: TurnLog = TurnLog(fate: 42, rejections: [], repaired: false,
                                            inputTokens: 0, outputTokens: 0)) -> AppliedTurn {
        AppliedTurn(playerText: playerText, narration: narration, newDate: newDate, ledger: ledger,
                    streamChanges: streamChanges, decisions: decisions, lifeState: lifeState,
                    cast: cast, events: events, log: log)
    }

    static func gift(_ amount: Int64, from giver: String, on date: GameDate = TestChat.date,
                     source: SourceType = .gift) -> NewLedgerEntry {
        NewLedgerEntry(date: date, sourceType: source, amountMinor: amount,
                       reason: "a gift", counterparty: giver, origin: .narrator)
    }
}
