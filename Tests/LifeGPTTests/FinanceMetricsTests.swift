import Foundation
import Testing
import LifeCore
@testable import LifeGPT

@Suite @MainActor struct FinanceMetricsTests {
    private let texas = JurisdictionRef(countryID: "US", subdivisionID: "US-TX")
    private let start = GameDate(year: 2004, month: 1, day: 1)

    private func fixture() throws -> (store: LifeStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lifegpt-metrics-\(UUID())")
        let library = try ChatLibrary(directory: directory)
        var character = NewCharacter(name: "Company owner", birthplace: "Texas, United States", birthYear: 1974,
            appearance: "Tall", startingAge: 30, background: nil, familyWealthTier: .wealthy)
        character.birthJurisdiction = texas; character.startingJurisdiction = texas
        let store = try library.createChat(character: character, economy: .sampleUS2005).store
        var settings = SessionSettings(); settings.playStyle = .sandbox; settings.household = .familySupported
        settings.contextLookupMode = .off
        try store.updateSettings(settings, swingDial: 1, replyLengthWords: 200)
        try store.updateBusinessSimulation(businessChanges: [.init(action: .create, id: "company", name: "Company",
            accountId: "company", jurisdiction: texas, legalStructure: .incorporated, effectiveFrom: start.iso)],
            expectedRevision: store.revision())
        return (store, directory)
    }

    private func advance(_ store: LifeStore) async throws {
        _ = try await TurnProcessor(store: store, narrator: MetricsAdvanceNarrator(), fate: MetricsFate())
            .play("Advance one month.", skipTime: .init(unit: .months, amount: 1))
    }

    @Test func reservingThenRemittingTaxesDoesNotSubtractTheLiabilityTwice() async throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = try LifeSnapshot(store: store)
        try store.updateBusinessSimulation(obligationChanges: [.init(action: .start, id: "revenue", businessId: "company",
            kind: .revenue, name: "Gross revenue", monthlyMinor: 5_000_000, fromAccountId: "company", effectiveFrom: start.iso)],
            expectedRevision: store.revision())
        try await advance(store)
        let reserved = try LifeSnapshot(store: store)
        #expect(reserved.reservedTaxes > 0 && reserved.unpaidObligations == reserved.reservedTaxes)
        #expect(reserved.balance + reserved.reservedTaxes == initial.balance + 5_000_000)
        #expect(reserved.netWorth == initial.netWorth + 5_000_000 - reserved.reservedTaxes)
        #expect(!reserved.ledger.contains { $0.reason.contains("Tax remittance") })
        try store.updateBusinessSimulation(obligationChanges: [.init(action: .end, id: "revenue",
            effectiveFrom: reserved.character.currentDate.iso)], expectedRevision: store.revision())
        try await advance(store)
        let remitted = try LifeSnapshot(store: store)
        #expect(remitted.reservedTaxes == 0 && remitted.unpaidObligations == 0)
        #expect(remitted.netWorth == reserved.netWorth)
        #expect(remitted.ledger.filter { $0.reason.contains("Tax remittance") }.reduce(Int64(0)) { $0 + $1.amountMinor } == -reserved.reservedTaxes)
    }

    @Test func unpaidOwnerNetSalaryIsAnInternalReceivableUntilFunded() async throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = try LifeSnapshot(store: store)
        try store.updateBusinessSimulation(obligationChanges: [.init(action: .start, id: "salary", businessId: "company",
            kind: .ownerSalary, name: "Owner gross salary", monthlyMinor: 150_000, fromAccountId: "company",
            toAccountId: "personal", jurisdiction: texas, taxResidence: texas, effectiveFrom: start.iso)],
            expectedRevision: store.revision())
        try await advance(store)
        let unpaid = try LifeSnapshot(store: store)
        let salary = try #require(unpaid.business.payables.first { $0.kind == .ownerSalary })
        #expect(salary.amountMinor == 150_000 && salary.paidMinor == 0 && salary.withholdingMinor > 0)
        #expect(unpaid.personalBalance == initial.personalBalance && unpaid.businessCash == 0)
        let netReceivable = salary.amountMinor - salary.withholdingMinor
        let externalCharges = unpaid.business.payables.filter { $0.kind == .tax }.reduce(Int64(0)) { $0 + $1.remainingMinor }
        #expect(unpaid.internalReceivables == netReceivable)
        #expect(unpaid.netWorth == initial.netWorth - salary.withholdingMinor - externalCharges)
        try store.updateBusinessSimulation(obligationChanges: [.init(action: .end, id: "salary",
            effectiveFrom: unpaid.character.currentDate.iso)], expectedRevision: store.revision())
        try BankingEngine.manage(store: store, openings: [], changes: [], transfers: [
            .init(fromAccount: "personal", toAccount: "company", amountMinor: unpaid.unpaidObligations,
                  reason: "Explicit owner capital funding of unpaid payroll")], expectedRevision: store.revision())
        try await advance(store)
        let funded = try LifeSnapshot(store: store)
        #expect(funded.internalReceivables == 0)
        #expect(funded.business.payables.first { $0.kind == .ownerSalary }?.remainingMinor == 0)
        #expect(funded.netWorth == unpaid.netWorth)
        #expect(funded.reservedTaxes == salary.withholdingMinor + externalCharges)
    }
}

private struct MetricsAdvanceNarrator: Narrator {
    func narrate(_ request: NarratorRequest) async throws -> NarratorResult {
        NarratorResult(output: TurnOutput(resolution: Resolution(zoom: .scene,
            timeAdvance: request.requestedTime ?? .init(unit: .months, amount: 1)), narration: "The month passes."), inputTokens: 0, outputTokens: 0)
    }
    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult { try await narrate(request) }
}

private struct MetricsFate: FateSource {
    func roll() -> Int { 50 }
}
