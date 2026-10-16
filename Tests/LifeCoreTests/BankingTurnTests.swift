import Foundation
import Testing
@testable import LifeCore

@Suite struct BankingTurnTests {
    private let businessAccount = AccountOpening(id: "business", name: "Studio business", kind: .business)
    private let savingsAccount = AccountOpening(id: "savings", name: "Personal reserve", kind: .savings)

    @Test(arguments: [HouseholdSupport.independent, .familySupported])
    func fiftyThousandMonthlyBusinessAndPersonalSupportSettleSeparately(_ household: HouseholdSupport) async throws {
        let store = try TestChat.chat(TestChat.library()).store
        var settings = SessionSettings()
        settings.household = household
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        let revision = try store.revision()
        let skip = TimeAdvance(unit: .months, amount: 3)
        var proposed = output("The studio becomes profitable while your family support continues.", time: skip, streams: [
            .init(action: .start, name: "Studio net profit", kind: .business, tier: nil,
                  monthlyMinor: 5_000_000, accountId: "business", effectiveFrom: "2020-02-15",
                  reason: "Established client contracts produce $50,000 in net monthly profit after business expenses."),
            .init(action: .start, name: "Family support", kind: .allowance, tier: nil,
                  monthlyMinor: 150_000, accountId: "personal", effectiveFrom: "2020-01-01",
                  reason: "Your family provides $1,500 each month for personal spending.")])
        proposed.resolution.accountOpenings = [businessAccount]
        let narrator = ScriptedNarrator(narrate: [.output(proposed)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42]))

        let result = try await processor.play("I run the studio over the next three months.", skipTime: skip)

        #expect(!result.repaired && result.rejections.isEmpty)
        #expect(narrator.repairCalls == 0)
        #expect(narrator.lastRequest?.requestedTime == skip)
        #expect(try store.character().currentDate.iso == "2020-04-01")
        let accounts = try store.accounts()
        let personal = try #require(accounts.first { $0.id == "personal" })
        let business = try #require(accounts.first { $0.id == "business" })
        let expectedBills: Int64 = household == .independent ? 360_000 : 0
        #expect(business.balanceMinor == 10_000_000)
        #expect(personal.balanceMinor == 175_000 + 450_000 - expectedBills)
        #expect(try store.balanceMinor() == business.balanceMinor + personal.balanceMinor)
        let ledger = try store.ledger(limit: 100)
        let profits = ledger.filter { $0.sourceType == .businessProfit }
        #expect(profits.map(\.date.iso) == ["2020-04-01", "2020-03-01"])
        #expect(profits.allSatisfy { $0.accountId == "business" && $0.amountMinor == 5_000_000 })
        let support = ledger.filter { $0.sourceType == .allowance }
        #expect(support.count == 3)
        #expect(support.allSatisfy { $0.accountId == "personal" && $0.amountMinor == 150_000 })
        let bills = ledger.filter { $0.sourceType == .livingCost }
        #expect(bills.count == (household == .independent ? 3 : 0))
        #expect(bills.allSatisfy { $0.accountId == "personal" })
        #expect(try store.positions().isEmpty)
        let businessStream = try #require(store.incomeStreams().first { $0.kind == .business })
        #expect(businessStream.startedOn.iso == "2020-02-15")
        #expect(businessStream.accountId == "business")
        #expect(try store.revision() == revision + 1)
    }

    @Test func narratedTransfersUsePairedEntriesAndPreserveTotalCash() async throws {
        let store = try TestChat.chat(TestChat.library()).store
        let initialTotal = try store.balanceMinor()
        var first = output("You separate the business float and your reserve.")
        first.resolution.accountOpenings = [businessAccount, savingsAccount]
        first.resolution.transfers = [
            AccountTransfer(fromAccount: "personal", toAccount: "business", amountMinor: 100_000,
                            reason: "Move the business float into its account."),
            AccountTransfer(fromAccount: "business", toAccount: "savings", amountMinor: 25_000,
                            reason: "Set aside a cash reserve.")]
        var second = output("You move part of the reserve back to your personal account.")
        second.resolution.transfers = [
            AccountTransfer(fromAccount: "savings", toAccount: "personal", amountMinor: 10_000,
                            reason: "Return unused reserve cash.")]
        let narrator = ScriptedNarrator(narrate: [.output(first), .output(second)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42, 42]))

        _ = try await processor.play("I organize my accounts and move money between them.")
        #expect(try store.balanceMinor() == initialTotal)
        #expect(try store.accounts().map(\.balanceMinor) == [75_000, 75_000, 25_000])
        _ = try await processor.play("I transfer $100 from savings back to my personal account.")

        #expect(try store.balanceMinor() == initialTotal)
        #expect(try store.accounts().map(\.balanceMinor) == [85_000, 75_000, 15_000])
        let entries = try store.ledger(limit: 20).filter { $0.sourceType == .transfer }
        #expect(entries.count == 6)
        #expect(entries.reduce(Int64(0)) { $0 + $1.amountMinor } == 0)
        #expect(entries.filter { $0.amountMinor > 0 }.count == 3)
        #expect(entries.filter { $0.amountMinor < 0 }.count == 3)
        #expect(entries.allSatisfy { $0.origin == .engine && $0.counterparty != nil })
        #expect(try store.incomeStreams().isEmpty)
        #expect(narrator.repairCalls == 0)
    }

    @Test func linkedIncomeReplacesLegacyPathProfitEvenAfterTheIncomeEnds() async throws {
        let store = try TestChat.chat(TestChat.library()).store
        var settings = SessionSettings()
        settings.household = .familySupported
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        var established = TestChat.turn()
        established.paths = [OpportunityPath(id: "studio", title: "Established studio", stage: .profit,
                                               startedOn: GameDate(year: 2019, month: 1, day: 1))]
        try store.apply(established)
        let personalBefore = try store.balanceMinor()
        let skip = TimeAdvance(unit: .months, amount: 2)
        var start = output("The studio now has a recorded monthly net profit.", time: skip, streams: [
            .init(action: .start, name: "Contract earnings", kind: .business, tier: nil,
                  monthlyMinor: 5_000_000, accountId: "business", pathId: "studio",
                  effectiveFrom: "2020-01-01", reason: "The established studio earns $50,000 in monthly net profit.")])
        start.resolution.accountOpenings = [businessAccount]
        let end = output("The contracts finish and the recorded income ends.", time: skip, streams: [
            .init(action: .end, name: "Contract earnings", kind: nil, tier: nil, monthlyMinor: nil,
                  effectiveFrom: "2020-04-01")])
        let later = output("Two more months pass without new contracts.", time: skip)
        let narrator = ScriptedNarrator(narrate: [.output(start), .output(end), .output(later)])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42, 42, 42]))

        _ = try await processor.play("I record the studio's actual profit and continue for two months.", skipTime: skip)
        #expect(try store.accounts().map(\.balanceMinor) == [personalBefore, 10_000_000])
        #expect(try store.ledger(limit: 100).filter { $0.sourceType == .businessProfit }.count == 2)
        _ = try await processor.play("The contracts finish in April; I wait until May.", skipTime: skip)
        #expect(try store.balanceMinor() == personalBefore + 10_000_000)
        _ = try await processor.play("I wait another two months while looking for clients.", skipTime: skip)

        #expect(try store.character().currentDate.iso == "2020-07-01")
        #expect(try store.accounts().map(\.balanceMinor) == [personalBefore, 10_000_000])
        let profits = try store.ledger(limit: 100).filter { $0.sourceType == .businessProfit }
        #expect(profits.count == 2)
        #expect(profits.allSatisfy { $0.accountId == "business" && $0.amountMinor == 5_000_000 })
        #expect(profits.map(\.date.iso) == ["2020-03-01", "2020-02-01"])
        #expect(try store.incomeStreams().first?.endedOn?.iso == "2020-04-01")
        #expect(try store.incomeStreams().first?.pathId == "studio")
        #expect(try store.paths().first?.stage == .profit)
        #expect(narrator.repairCalls == 0)
    }

    @Test(arguments: [false, true])
    func failedRepairLeavesAllBankingStateUnchanged(_ repairTransportFails: Bool) async throws {
        let store = try TestChat.chat(TestChat.library()).store
        try store.applyFinancialChanges(accountOpenings: [savingsAccount], streamChanges: [
            .init(action: .start, name: "Family support", kind: .allowance, tier: nil, monthlyMinor: 1_000)],
            ledger: [], expectedRevision: 0)
        let accountsBefore = try store.accounts()
        let streamsBefore = try store.incomeStreams()
        let ledgerBefore = try store.ledger(limit: 100)
        let revisionBefore = try store.revision()
        let positionsBefore = try store.positions()
        let dateBefore = try store.character().currentDate
        let skip = TimeAdvance(unit: .months, amount: 2)
        var invalid = output("The studio earns money and you move some into reserve.", time: skip, streams: [
            .init(action: .start, name: "Studio net profit", kind: .business, tier: nil,
                  monthlyMinor: 5_000_000, accountId: "business", effectiveFrom: "2020-01-01",
                  reason: "Existing commercial contracts earn $50,000 in monthly net profit."),
            .init(action: .change, name: "Family support", kind: nil, tier: nil, monthlyMinor: 2_000,
                  effectiveFrom: "2020-01-01", reason: "The family doubles its monthly personal support.")])
        invalid.resolution.accountOpenings = [businessAccount]
        invalid.resolution.transfers = [
            AccountTransfer(fromAccount: "business", toAccount: "savings", amountMinor: 100_000,
                            reason: "Reserve part of the business earnings."),
            AccountTransfer(fromAccount: "business", toAccount: "unknown", amountMinor: 50_000,
                            reason: "This destination does not exist.")]
        let repair: ScriptedNarrator.Step = repairTransportFails
            ? .error(ProviderError.http(status: 503, body: "unavailable")) : .output(invalid)
        let narrator = ScriptedNarrator(narrate: [.output(invalid)], repair: [repair])
        let processor = TurnProcessor(store: store, narrator: narrator, fate: FixedFate([42]))

        await #expect(throws: TurnError.self) {
            _ = try await processor.play("I record profits and move some earnings to savings.", skipTime: skip)
        }

        #expect(narrator.repairCalls == 1)
        #expect(narrator.rejectionsGiven.first?.contains { $0.contains("transfers") } == true)
        #expect(try store.accounts() == accountsBefore)
        #expect(try store.incomeStreams() == streamsBefore)
        #expect(try store.ledger(limit: 100) == ledgerBefore)
        #expect(try store.revision() == revisionBefore)
        #expect(try store.positions() == positionsBefore)
        #expect(try store.character().currentDate == dateBefore)
        #expect(try store.recentMessages(limit: 10).isEmpty)
        #expect(try store.turnLogs().isEmpty)
    }
}
