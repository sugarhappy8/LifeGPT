import Foundation
import Testing
@testable import LifeCore

@Suite struct PlayStyleTests {
    @Test func oldSavesDefaultToSimulationAndSandboxPersists() throws {
        #expect(try JSONDecoder().decode(SessionSettings.self, from: Data("{}".utf8)).playStyle == .simulation)
        let library = try TestChat.library()
        let chat = try TestChat.chat(library)
        var settings = SessionSettings(); settings.playStyle = .sandbox
        try chat.store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        #expect(try library.openChat(id: chat.id).sessionSettings().playStyle == .sandbox)
    }

    @Test func sandboxRelaxesEconomicGatesButNeverSpendsOtherAccounts() {
        var context = MoneyContext(economy: .sampleUS2005, familyTier: .middle, balanceMinor: 100,
                                   elapsedDays: 0, fate: 1, castNames: [], daysSinceLastWindfall: 0)
        context.accountBalances = ["personal": 100, "business": 5_000_000]
        let gain = ProposedMoneyEntry(sourceType: .windfall, amountMinor: 5_000_000, reason: "A declared fictional prize")
        #expect(MoneyValidator.validate([gain], in: context).first != .accepted)
        context.playStyle = .sandbox
        #expect(MoneyValidator.validate([gain], in: context) == [.accepted])
        let debit = ProposedMoneyEntry(sourceType: .expense, amountMinor: -101, reason: "Personal shopping")
        #expect(MoneyValidator.validate([debit], in: context).first != .accepted)
        let unknown = ProposedMoneyEntry(sourceType: .adjustment, amountMinor: 100, reason: "Correction", accountId: "missing")
        #expect(MoneyValidator.validate([unknown], in: context).first != .accepted)
    }

    @Test func sandboxPathsHonorEstablishedBusinessesWithoutChargingFictionalCapital() {
        let change = PathUpdate(id: "website", title: "Website", stage: .profit, notes: "Already established")
        let sandbox = PathEngine.plan([change], existing: [], date: TestChat.date, age: 30,
            economy: .sampleUS2005, balance: 0, fate: 1, playStyle: .sandbox)
        #expect(sandbox.rejections.isEmpty && sandbox.paths.first?.stage == .profit && sandbox.ledger.isEmpty)
        let simulation = PathEngine.plan([change], existing: [], date: TestChat.date, age: 30,
            economy: .sampleUS2005, balance: 0, fate: 1)
        #expect(!simulation.rejections.isEmpty && simulation.paths.isEmpty)
    }

    @Test func decodedProviderReplyRecordsFiftyThousandAndPaysExactlyOnce() async throws {
        let store = try TestChat.chat(TestChat.library()).store
        var settings = SessionSettings(); settings.playStyle = .sandbox; settings.household = .familySupported
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        let json = #"""
        {"resolution":{"zoom":"scene","time_advance":{"unit":"days","amount":0},"money":[],
          "income_streams":[{"action":"start","name":"Website net profit","kind":"business","monthly_minor":5000000,
          "account_id":"website","path_id":"website","effective_from":"2020-01-01","reason":"Established subscription business after operating costs"}],
          "account_openings":[{"id":"website","name":"Website business","kind":"business"}],
          "path_updates":[{"id":"website","title":"Website","stage":"profit","notes":"Established subscribers"}],
          "decisions":[],"life_state_changes":[],"cast_updates":[],"events":[],"crime_attempt":null},
          "narration":"Your website now earns $50,000 net profit each month. Its business account is ready for the next payment."}
        """#
        let provider = StubProvider(responses: [StubProvider.reply(json)])
        let result = try await TurnProcessor(store: store, narrator: LLMNarrator(provider: provider), fate: FixedFate([1]))
            .play("My website earns USD 50,000 net profit per month, from today, in its own business account.")
        #expect(!result.repaired && provider.requests.count == 1)
        #expect(try store.accounts().first { $0.id == "website" }?.balanceMinor == 0)
        let stream = try #require(store.incomeStreams().first)
        #expect(stream.monthlyMinor == 5_000_000 && stream.accountId == "website" && stream.pathId == "website")
        let next = ScriptedNarrator(narrate: [.output(output("A profitable month.", time: .init(unit: .months, amount: 1)))])
        _ = try await TurnProcessor(store: store, narrator: next, fate: FixedFate([1])).play("Skip one month.")
        #expect(try store.accounts().first { $0.id == "website" }?.balanceMinor == 5_000_000)
        #expect(try store.accounts().first { $0.id == "personal" }?.balanceMinor == 175_000)
        #expect(try store.ledger(limit: 20).filter { $0.sourceType == .businessProfit }.count == 1)
        #expect(try OOCResponder.answer("accounts", store: store).contains("Website business [website]: 50,000.00 USD"))
        #expect(try OOCResponder.answer("income", store: store).contains("50,000.00 USD per month (business), paid to website"))
        #expect(provider.requests[0].user.contains("Play style: Sandbox"))
        #expect(!provider.requests[0].user.contains("A windfall needs a fate roll"))
    }

    @Test(arguments: [PlayStyle.simulation, .sandbox])
    func cashCorrectionsRequireSandboxAndCommitAsDelta(_ style: PlayStyle) async throws {
        let store = try TestChat.chat(TestChat.library()).store
        var settings = SessionSettings(); settings.playStyle = style
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        let revision = try store.revision()
        let correction = output("You record the agreed cash correction.", money: [
            .init(sourceType: .adjustment, amountMinor: 5_000_000, reason: "Player-authorized correction for a missing historical receipt")])
        let narrator = ScriptedNarrator(narrate: [.output(correction)], repair: [.output(correction)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([1]))
        if style == .sandbox {
            _ = try await processor.play("Correct my cash by adding USD 50,000 once.")
            #expect(try store.balanceMinor() == 5_175_000)
            #expect(try store.revision() == revision + 1 && narrator.repairCalls == 0)
        } else {
            await #expect(throws: TurnError.self) { _ = try await processor.play("Correct my cash by adding USD 50,000 once.") }
            #expect(try store.balanceMinor() == 175_000 && store.revision() == revision)
        }
    }
}
