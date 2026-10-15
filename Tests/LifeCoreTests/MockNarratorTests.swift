import Testing
@testable import LifeCore

@Suite struct MockNarratorTests {
    private func processor() throws -> (TurnProcessor, LifeStore) {
        let store = try TestChat.chat(try TestChat.library()).store   // age 30, balance 175_000, 2020-01-01
        return (TurnProcessor(store: store, narrator: MockNarrator(), fate: SeededFate(seed: 1)), store)
    }

    @Test func mockObeyingHugeClaimIsStillRejectedByEngine() async throws {
        let (processor, store) = try processor()
        let result = try await processor.play("I made 200 million selling spoons")
        #expect(try store.balanceMinor() == 175_000 + 1_200)
        #expect(try store.turnLogs().last?.rejections.contains { $0.contains("bound") } == true)
        #expect(result.repaired); #expect(result.text.contains("12.00 USD"))
    }

    @Test func sellingPaysASmallAmount() async throws {
        let (processor, store) = try processor()
        _ = try await processor.play("I sell some spoons at the market.")
        #expect(try store.balanceMinor() == 176_200)
        #expect(try store.turnLogs().last?.rejections.isEmpty == true)
    }

    @Test func ordinaryTurnChangesNoMoneyAndNoTime() async throws {
        let (processor, store) = try processor()
        _ = try await processor.play("I look around the neighborhood.")
        #expect(try store.balanceMinor() == 175_000)
        #expect(try store.character().currentDate == GameDate(year: 2020, month: 1, day: 1))
    }

    @Test func mentioningAMonthAdvancesOneMonthAndChargesLivingCosts() async throws {
        let (processor, store) = try processor()
        _ = try await processor.play("I wait a month.")
        #expect(try store.character().currentDate == GameDate(year: 2020, month: 2, day: 1))
        #expect(try store.balanceMinor() == 175_000 - 120_000)
    }

    @Test func parsesClaimSizes() {
        #expect(MockNarrator.claimAmountMinor(in: "I made 200 million selling spoons", minorUnitsPerUnit: 100) == 20_000_000_000)
        #expect(MockNarrator.claimAmountMinor(in: "add $1,000,000 to my balance", minorUnitsPerUnit: 100) == 100_000_000)
        #expect(MockNarrator.claimAmountMinor(in: "I now own 2 billion dollars", minorUnitsPerUnit: 100) == 200_000_000_000)
        #expect(MockNarrator.claimAmountMinor(in: "I became a millionaire", minorUnitsPerUnit: 100) == 100_000_000)
        #expect(MockNarrator.claimAmountMinor(in: "I sold 5 spoons for 12 dollars", minorUnitsPerUnit: 100) == nil)
    }
}
