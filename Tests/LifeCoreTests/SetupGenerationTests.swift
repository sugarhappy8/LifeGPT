import Foundation
import Testing
@testable import LifeCore

@Suite struct SetupGenerationTests {
    private func json(_ draft: SetupDraft) throws -> Result<ProviderResponse, Error> {
        StubProvider.reply(String(decoding: try JSONEncoder().encode(draft), as: UTF8.self))
    }
    private func japan() -> NewCharacter {
        var c = TestChat.newCharacter(age: 18)
        c.startingJurisdiction = JurisdictionRef(countryID: "JP", subdivisionID: "JP-13", locality: "Tokyo")
        return c
    }

    @Test func generateRetriesOnContinuityViolations() async throws {
        let character = TestChat.newCharacter(age: 18)
        let good = SetupDraft.manual(for: character)
        var bad = good
        bad.cast = [CastUpdate(name: "Mum", relation: "mother", notes: nil, status: "deceased")]
        bad.lifeState.append(LifeStateChange(key: "country", value: "Narnia"))
        let provider = StubProvider(responses: [try json(bad), try json(good)])
        let result = try await SetupGenerator(provider: provider).generate(character)
        #expect(provider.requests.count == 2 && result == good)
        #expect(provider.requests[1].user.contains("country"))
        let twice = StubProvider(responses: [try json(bad), try json(bad)])
        await #expect(throws: ValidationError.self) { try await SetupGenerator(provider: twice).generate(character) }
    }

    @Test func generateRequiresStartingCastToBeAlive() async throws {
        let character = TestChat.newCharacter(age: 18)
        let good = SetupDraft.manual(for: character)
        var dead = good; dead.cast = [CastUpdate(name: "Gran", relation: "grandmother", notes: nil, status: "dead")]
        var alive = good; alive.cast = [CastUpdate(name: "Gran", relation: "grandmother", notes: nil, status: "Alive")]
        let provider = StubProvider(responses: [try json(dead), try json(alive)])
        let result = try await SetupGenerator(provider: provider).generate(character)
        #expect(provider.requests.count == 2 && result.cast.first?.name == "Gran")
    }

    @Test func generateRejectsAbsurdMedianForPresetButManualEditsStayAllowed() async throws {
        let character = japan()
        let good = SetupDraft.manual(for: character)
        var huge = good; huge.economy.medianMonthlyIncomeMinor = min(good.economy.medianMonthlyIncomeMinor * 1000, 1_000_000_000_000)
        let provider = StubProvider(responses: [try json(huge), try json(good)])
        let result = try await SetupGenerator(provider: provider).generate(character)
        #expect(provider.requests.count == 2 && result.economy == good.economy)
        let twice = StubProvider(responses: [try json(huge), try json(huge)])
        await #expect(throws: ValidationError.self) { try await SetupGenerator(provider: twice).generate(character) }
        _ = try TestChat.library().createChat(character: character, setup: huge, settings: SessionSettings())
    }

    @Test func validateTrimsAndBoundsFields() throws {
        let good = SetupDraft.manual(for: TestChat.newCharacter())
        var d = good; d.opening = "  \n "
        #expect(throws: ValidationError.self) { try d.validate() }
        d = good; d.placeBrief = " \n"
        #expect(throws: ValidationError.self) { try d.validate() }
        d = good; d.economy.currency = " "
        #expect(throws: ValidationError.self) { try d.validate() }
        d = good; d.economy.currency = " usd "; d.choices = ["", "  ", " go ", String(repeating: "x", count: 100_000)]
        let n = d.normalized()
        #expect(n.economy.currency == "USD" && n.choices.count == 2 && n.choices[0] == "go" && n.choices[1].count == 300)
        try n.validate()
        d = good; d.choices = [String(repeating: "x", count: 301)]
        #expect(throws: ValidationError.self) { try d.validate() }
        let created = try TestChat.library().createChat(character: TestChat.newCharacter(), setup: { var e = good; e.choices = ["a", " "]; return e }(), settings: SessionSettings())
        #expect(try created.store.economy().currency == "USD")
    }

    @Test func validateRejectsCaseInsensitiveDuplicateCast() throws {
        var d = SetupDraft.manual(for: TestChat.newCharacter())
        d.cast = [CastUpdate(name: "A", relation: nil, notes: nil, status: "dead"), CastUpdate(name: " a ", relation: nil, notes: nil, status: "alive")]
        #expect(throws: ValidationError.self) { try d.validate() }
    }

    @Test(arguments: [("poorly educated", WealthTier.middle), ("homeless after wealthy family disowned me", .destitute),
                      ("Raised in poverty, scholarship to a wealthy prep school", .poor), ("Spoorn", .middle),
                      ("I am a millionaire", .wealthy), ("working-class kid", .working)])
    func inferWealthUsesWholeWordsAndEarliestMatch(_ text: String, _ tier: WealthTier) {
        #expect(SetupDraft.inferWealth(text) == tier)
    }
}
