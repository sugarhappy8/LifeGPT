import Foundation
import Testing
@testable import LifeCore

@Suite struct LifeRulesTests {
    @Test func oldSettingsKeepVoiceToneAndLength() throws {
        let old = #"{"voiceBible":"Quiet and direct","automaticLength":true,"contentTone":"Gentle"}"#
        let settings = try JSONDecoder().decode(SessionSettings.self, from: Data(old.utf8))
        #expect(settings.voiceBible == "Quiet and direct" && settings.automaticLength && settings.contentTone == "Gentle")
        #expect(settings.difficulty == 50 && settings.household == .automatic)
        #expect(try JSONDecoder().decode(SessionSettings.self, from: Data("{}".utf8)) == SessionSettings())
    }

    @Test func householdUsesCurrentFactsAndExplicitPreferences() {
        var settings = SessionSettings()
        #expect(HouseholdSupport.resolve(settings: settings, state: [:], background: "I live with my parents.") == .familySupported)
        #expect(HouseholdSupport.resolve(settings: settings, state: ["residence": "My own apartment"], background: "UAE royalty") == .independent)
        #expect(HouseholdSupport.resolve(settings: settings, state: ["household_support": "independent"], background: "Living with my parents") == .independent)
        settings.household = .familySupported
        #expect(HouseholdSupport.resolve(settings: settings, state: ["household_support": "independent"], background: nil) == .familySupported)
        settings.household = .independent
        #expect(HouseholdSupport.resolve(settings: settings, state: [:], background: "UAE royalty") == .independent)
    }

    @Test(arguments: ["UAE royalty", "Emirati royal family", "royailty in the UAE"])
    func royalPremiseIsEstablishedWithoutAFreeCashDeposit(_ background: String) async throws {
        var character = TestChat.newCharacter(age: 18)
        character.birthplace = "Abu Dhabi, UAE"; character.background = background
        let draft = SetupDraft.manual(for: character)
        #expect(draft.familyWealthTier == .ultraWealthy)
        #expect(draft.lifeState.contains { $0.key == "household_support" && $0.value == "family_supported" })
        #expect(draft.opening.contains("Your place in a royal family is already part of this life"))
        let store = try TestChat.library().createChat(character: character, setup: draft, settings: SessionSettings()).store
        #expect(try store.balanceMinor() == StartingMoney.balanceMinor(forAge: 18, economy: draft.economy))
        let narrator = ScriptedNarrator(narrate: [.output(output("A month at home.", time: .init(unit: .months, amount: 1)))])
        _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50])).play("I spend a month with my family.")
        #expect(try store.ledger(limit: 20).count == 1)
        #expect(try store.positions().isEmpty)
        let prompt = PromptRenderer.render(try #require(narrator.lastRequest))
        #expect(prompt.system.contains("actual membership in that fictional royal family"))
        #expect(prompt.user.contains(background) && prompt.user.contains("Personal monthly rent and living costs: 0.00 USD"))
    }

    @Test func setupModelReceivesRoyalAndHouseholdInstructions() async throws {
        var character = TestChat.newCharacter(age: 18); character.background = "UAE royalty"
        let draft = SetupDraft.manual(for: character)
        let json = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
        let provider = StubProvider(responses: [StubProvider.reply(json)])
        let result = try await SetupGenerator(provider: provider).generate(character)
        #expect(result == draft)
        #expect(provider.requests[0].system.contains("Honor the user's identity and background"))
        #expect(provider.requests[0].system.contains("Living with parents means family_supported"))
    }

    @Test func familySupportLeavesWagesAndOptionalPurchasesIntact() async throws {
        let store = try TestChat.chat(try TestChat.library(), age: 18).store
        try store.seedHistory(cast: [], decisions: [], lifeState: [.init(key: "household_support", value: "family_supported")])
        let date = try store.character().currentDate
        try store.apply(TestChat.turn(newDate: date, streamChanges: [.init(action: .start, name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 200_000)]))
        let balance = try store.balanceMinor()
        let narrator = ScriptedNarrator(narrate: [.output(output("Three months of work at home.", time: .init(unit: .months, amount: 3),
            money: [.init(sourceType: .expense, amountMinor: -10_000, reason: "A personal bicycle")]))])
        _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42])).play("I work for three months while living with my parents.")
        #expect(try store.balanceMinor() == balance + 600_000 - 10_000)
        #expect(try store.ledger(limit: 20).allSatisfy { $0.sourceType != .livingCost && $0.sourceType != .loan })
        #expect(try store.positions().isEmpty)
    }

    @Test func movingOutChangesFutureBillsAndExplicitSettingsPersist() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        try store.seedHistory(cast: [], decisions: [], lifeState: [.init(key: "household_support", value: "family_supported")])
        let balance = try store.balanceMinor()
        let narrator = ScriptedNarrator(narrate: [
            .output(output("After a month at home, you move out.", time: .init(unit: .months, amount: 1), lifeState: [.init(key: "household_support", value: "independent")])),
            .output(output("A month in your apartment.", time: .init(unit: .months, amount: 1))),
            .output(output("Your family covers your costs.", time: .init(unit: .months, amount: 1)))
        ])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50]))
        _ = try await processor.play("I spend a month preparing to move, then leave home.")
        #expect(try store.balanceMinor() == balance)
        _ = try await processor.play("I spend a month in my new apartment.")
        #expect(try store.balanceMinor() == balance - 120_000)
        var settings = SessionSettings(); settings.household = .familySupported; settings.difficulty = 15
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        #expect(try store.sessionSettings() == settings)
        _ = try await processor.play("My family covers my bills this month.")
        #expect(try store.balanceMinor() == balance - 120_000)
        #expect(try store.ledger(limit: 20).filter { $0.sourceType == .livingCost }.count == 1)
    }

    @Test func householdSettingAlsoChangesLoanAffordability() throws {
        let stream = IncomeStream(name: "Shop", kind: .wage, tier: "entry", monthlyMinor: 120_000, startedOn: TestChat.date)
        let action = FinancialAction(action: .borrow, id: "loan", name: "Loan", amountMinor: 100_000)
        for household in [HouseholdSupport.familySupported, .independent] {
            let plan = try FinanceEngine.actions([action], date: TestChat.date, age: 18, economy: .sampleUS2005,
                streams: [stream], plan: .init(positions: [], balance: 0), household: household)
            #expect(plan.rejections.isEmpty == (household == .familySupported))
        }
    }

    @Test(arguments: ["Dad", "my father", "Gerald", " GERALD HALE "])
    func familyGiftUsesCanonicalIdentityAndStillEnforcesCooldown(_ giver: String) async throws {
        let store = try familyStore()
        let gift = output("Your father helps with college.", money: [.init(sourceType: .gift, amountMinor: 130_000, reason: "College support", counterparty: giver)])
        let narrator = ScriptedNarrator(narrate: [.output(gift), .output(gift)], repair: [.output(gift)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([43]))
        let start = try store.balanceMinor()
        let first = try await processor.play("Dad helps with college.")
        #expect(!first.repaired && narrator.repairCalls == 0)
        #expect(try store.balanceMinor() == start + 130_000)
        #expect(try store.ledger(limit: 1).first?.counterparty == "Gerald Hale")
        let revision = try store.revision()
        do { _ = try await processor.play("Dad helps again."); Issue.record("Cooldown should reject") }
        catch TurnError.validationFailed(let reasons) { #expect(reasons.contains { $0.contains("gap") }) }
        #expect(try store.revision() == revision && store.balanceMinor() == start + 130_000)
    }

    @Test func aliasesNeverGuessBetweenPeopleOrBypassDeath() async throws {
        let store = try familyStore()
        try store.seedHistory(cast: [.init(name: "Gerald Jones", relation: "friend", notes: nil, status: nil)], decisions: [], lifeState: [])
        let cast = try store.castMembers()
        #expect(CastIdentity.resolve("Gerald", in: cast) == nil)
        #expect(CastIdentity.resolve("Someone else", in: cast) == nil)
        #expect(CastIdentity.resolve("Dad", in: cast)?.name == "Gerald Hale")
        let bad = output("A gift after death.", money: [.init(sourceType: .gift, amountMinor: 100, reason: "Support", counterparty: "Dad")],
            cast: [.init(name: "Dad", relation: nil, notes: nil, status: "dead")])
        let narrator = ScriptedNarrator(narrate: [.output(bad)], repair: [.output(bad)])
        let revision = try store.revision()
        do { _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([100])).play("I visit my father."); Issue.record("Dead giver should reject") }
        catch TurnError.validationFailed(let reasons) { #expect(reasons.contains { $0.contains("dead person") }) }
        #expect(try store.revision() == revision)
        #expect(try store.castMembers().first { $0.name == "Gerald Hale" }?.status == "alive")
    }

    @Test func difficultyImprovesActualSuccessOddsMonotonically() {
        let passes = [0, 50, 100].map { difficulty in
            (1...100).filter { GameDifficulty.effectiveFate($0, difficulty: difficulty) >= 40 }.count
        }
        #expect(passes == [91, 61, 31])
        for raw in 1...100 {
            #expect(GameDifficulty.effectiveFate(raw, difficulty: 0) >= GameDifficulty.effectiveFate(raw, difficulty: 50))
            #expect(GameDifficulty.effectiveFate(raw, difficulty: 50) >= GameDifficulty.effectiveFate(raw, difficulty: 100))
        }
    }

    @Test(arguments: [0, 50, 100])
    func difficultyControlsBusinessGatesAndRecordsRawAndEffectiveFate(_ difficulty: Int) async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        var settings = SessionSettings(); settings.difficulty = difficulty; settings.household = .familySupported
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        var turn = TestChat.turn()
        turn.paths = [.init(id: "site", title: "Video site", stage: .capital, startedOn: TestChat.date.adding(days: -60))]
        try store.apply(turn)
        var launch = output("The website launches.")
        launch.resolution.pathUpdates = [.init(id: "site", title: "Video site", stage: .launch)]
        let narrator = ScriptedNarrator(narrate: [.output(launch)], repair: [.output(launch)])
        let revision = try store.revision()
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([20]))
        if difficulty == 0 {
            _ = try await processor.play("I launch the site.")
            #expect(try store.paths().first?.stage == .launch)
            #expect(try store.turnLogs().last?.fate == 20)
            #expect(try store.lifeState()["_engine_last_effective_fate"] == "50")
            #expect(try store.lifeState()["_engine_last_difficulty"] == "0")
        } else {
            await #expect(throws: TurnError.self) { _ = try await processor.play("I launch the site.") }
            #expect(try store.paths().first?.stage == .capital && store.revision() == revision)
        }
        let request = try #require(narrator.lastRequest)
        #expect(request.fate == GameDifficulty.effectiveFate(20, difficulty: difficulty))
        let prompt = PromptRenderer.render(request)
        #expect(prompt.user.contains("Difficulty: \(difficulty)/100"))
        if difficulty == 0 { #expect(prompt.user.contains("100,000 daily users")) }
    }

    @Test func easierDifficultyNeverBypassesMoneyCaps() async throws {
        let store = try familyStore()
        var settings = SessionSettings(); settings.difficulty = 0
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        let bad = output("An excessive gift.", money: [.init(sourceType: .gift, amountMinor: 9_000_000, reason: "Support", counterparty: "Dad")])
        let narrator = ScriptedNarrator(narrate: [.output(bad)], repair: [.output(bad)])
        let revision = try store.revision()
        await #expect(throws: TurnError.self) { _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([100])).play("Dad helps.") }
        #expect(try store.revision() == revision && store.messageCount() == 0)
    }

    @Test func malformedReplyThenNetworkFailureIsRetryableValidationFailure() async throws {
        let store = try TestChat.chat(try TestChat.library()).store
        let narrator = ScriptedNarrator(narrate: [.failure(.malformedOutput("bad JSON"))], repair: [.error(URLError(.notConnectedToInternet))])
        do { _ = try await TurnProcessor(store: store, narrator: narrator, fate: FixedFate([50])).play("I open a letter."); Issue.record("Expected failure") }
        catch TurnError.validationFailed(let reasons) {
            #expect(reasons.contains { $0.contains("bad JSON") })
            #expect(reasons.contains { $0.contains("Repair failed") })
        }
        #expect(try store.messageCount() == 0 && store.revision() == 0)
    }

    private func familyStore() throws -> LifeStore {
        let store = try TestChat.library().createChat(character: TestChat.newCharacter(tier: .wealthy), economy: .sampleUS2005).store
        try store.seedHistory(cast: [.init(name: "Gerald Hale", relation: "father", notes: nil, status: "alive")], decisions: [], lifeState: [])
        return store
    }
}
