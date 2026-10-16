import Foundation
import Testing
import LifeCore
@testable import LifeGPT

@Suite @MainActor struct FinanceManagerTests {
    @Test func financialChangesPersistAndRefreshWithoutAdvancingTheStory() throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let before = try #require(r.model.snapshot)
        let transferAmount: Int64 = 50_000
        let income = websiteIncome(date: before.character.currentDate)

        try r.model.updateFinances(
            accountOpenings: [AccountOpening(id: "website", name: "Website business", kind: .business)],
            streamChanges: [income],
            transfers: [AccountTransfer(fromAccount: "personal", toAccount: "website",
                amountMinor: transferAmount, reason: "Move existing savings into the business.")],
            expectedLifeID: before.character.id, expectedRevision: before.revision)

        let after = try #require(r.model.snapshot)
        #expect(after.revision == before.revision + 1)
        #expect(try r.store.revision() == after.revision)
        #expect(after.accounts == [
            BankAccount(id: "personal", name: "Personal", kind: .personal, balanceMinor: before.balance - transferAmount),
            BankAccount(id: "website", name: "Website business", kind: .business, balanceMinor: transferAmount)
        ])
        #expect(after.balance == before.balance)
        #expect(after.personalBalance == before.personalBalance - transferAmount)
        #expect(after.streams == [IncomeStream(name: "Website profit", kind: .business, tier: nil,
            monthlyMinor: 5_000_000, startedOn: before.character.currentDate, accountId: "website")])
        #expect(after.monthlyIncome == 5_000_000)
        let transfers = after.ledger.filter { $0.sourceType == .transfer }
        #expect(transfers.count == 2)
        #expect(transfers.reduce(Int64(0)) { $0 + $1.amountMinor } == 0)
        #expect(Set(transfers.map(\.accountId)) == Set(["personal", "website"]))
        #expect(after.ledger.filter { $0.sourceType != .transfer } == before.ledger)
        #expect(after.character.currentDate == before.character.currentDate)
        #expect(after.messages == before.messages && after.totalMessages == before.totalMessages)
        #expect(after.logs == before.logs)
        #expect(after.choices == before.choices)
        #expect(try r.store.recentMessages(limit: 100) == before.messages)

        let reopened = AppModel(paths: r.paths)
        let saved = try #require(reopened.snapshot)
        #expect(saved.revision == after.revision)
        #expect(saved.accounts == after.accounts && saved.streams == after.streams)
        #expect(saved.ledger == after.ledger)
        #expect(saved.messages == before.messages && saved.character.currentDate == before.character.currentDate)
    }

    @Test func changingAndEndingIncomePreservesItsHistoryWithoutDepositingCash() throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let before = try #require(r.model.snapshot)
        try r.model.updateFinances(
            accountOpenings: [AccountOpening(id: "website", name: "Website business", kind: .business)],
            streamChanges: [websiteIncome(date: before.character.currentDate)], transfers: [],
            expectedLifeID: before.character.id, expectedRevision: before.revision)

        let started = try #require(r.model.snapshot)
        try r.model.updateFinances(accountOpenings: [], streamChanges: [
            IncomeStreamChange(action: .change, name: "Website profit", kind: .business, tier: nil,
                monthlyMinor: 6_000_000, accountId: "website", effectiveFrom: before.character.currentDate.iso,
                reason: "Additional subscriptions increase recurring net profit.")
        ], transfers: [], expectedLifeID: before.character.id, expectedRevision: started.revision)

        let changed = try #require(r.model.snapshot)
        #expect(changed.revision == started.revision + 1)
        #expect(changed.streams.count == 2)
        #expect(changed.streams.first?.monthlyMinor == 5_000_000)
        #expect(changed.streams.first?.endedOn == before.character.currentDate)
        #expect(changed.streams.last?.monthlyMinor == 6_000_000 && changed.streams.last?.endedOn == nil)
        #expect(changed.monthlyIncome == 6_000_000)

        try r.model.updateFinances(accountOpenings: [], streamChanges: [
            IncomeStreamChange(action: .end, name: "Website profit", kind: nil, tier: nil, monthlyMinor: nil,
                effectiveFrom: before.character.currentDate.iso, reason: "The website closes.")
        ], transfers: [], expectedLifeID: before.character.id, expectedRevision: changed.revision)

        let ended = try #require(r.model.snapshot)
        #expect(ended.revision == before.revision + 3)
        #expect(ended.streams.count == 2 && ended.streams.allSatisfy { $0.endedOn == before.character.currentDate })
        #expect(ended.monthlyIncome == 0)
        #expect(ended.accounts.first { $0.id == "website" }?.balanceMinor == 0)
        #expect(ended.balance == before.balance && ended.ledger == before.ledger)
        #expect(ended.messages == before.messages && ended.character.currentDate == before.character.currentDate)
        #expect(try r.store.incomeStreams() == ended.streams)
    }

    @Test(arguments: [false, true])
    func staleCapturedRevisionCannotWriteFinancialChanges(_ externalEdit: Bool) throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let captured = try #require(r.model.snapshot)
        if externalEdit {
            try r.store.updateSettings(SessionSettings(), swingDial: 1, replyLengthWords: 500)
        } else {
            try r.model.updateFinances(
                accountOpenings: [AccountOpening(id: "savings", name: "Savings", kind: .savings)],
                streamChanges: [], transfers: [], expectedLifeID: captured.character.id, expectedRevision: captured.revision)
        }
        let revision = try r.store.revision()
        let accounts = try r.store.accounts()
        let ledger = try r.store.ledger(limit: 100)
        #expect(revision == captured.revision + 1)

        #expect(throws: ValidationError.self) {
            try r.model.updateFinances(
                accountOpenings: [AccountOpening(id: "stale-account", name: "Stale account", kind: .business)],
                streamChanges: [], transfers: [], expectedLifeID: captured.character.id, expectedRevision: captured.revision)
        }

        #expect(try r.store.revision() == revision)
        #expect(r.model.snapshot?.revision == revision)
        #expect(r.model.snapshot?.accounts == accounts)
        #expect(try r.store.accounts() == accounts)
        #expect(try r.store.ledger(limit: 100) == ledger)
        #expect(try r.store.incomeStreams().isEmpty)
        #expect(try r.store.recentMessages(limit: 100) == captured.messages)
        #expect(try r.store.character().currentDate == captured.character.currentDate)
    }

    @Test func staleLifeCannotEditAnotherLifeWithTheSameRevision() throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let captured = try #require(r.model.snapshot)
        let originalAccounts = try r.store.accounts()
        let library = try ChatLibrary(directory: r.paths.chats)
        let other = try library.createChat(character: character(name: "Another life"), economy: .sampleUS2005)
        try other.store.saveOpening("A different life begins.", choices: ["I look around."])
        r.model.openLife(other.id)
        let current = try #require(r.model.snapshot)
        #expect(current.character.id != captured.character.id)
        #expect(current.revision == captured.revision)

        #expect(throws: ValidationError.self) {
            try r.model.updateFinances(
                accountOpenings: [AccountOpening(id: "wrong-life-account", name: "Wrong life account", kind: .business)],
                streamChanges: [], transfers: [], expectedLifeID: captured.character.id, expectedRevision: captured.revision)
        }

        #expect(r.model.selection == other.id)
        #expect(r.model.snapshot?.character.id == current.character.id)
        #expect(r.model.snapshot?.revision == current.revision)
        #expect(try other.store.accounts() == current.accounts)
        #expect(try other.store.revision() == current.revision)
        #expect(try other.store.recentMessages(limit: 100) == current.messages)
        #expect(try other.store.character().currentDate == current.character.currentDate)
        #expect(try r.store.accounts() == originalAccounts)
        #expect(try r.store.revision() == captured.revision)
        #expect(try r.store.recentMessages(limit: 100) == captured.messages)
    }

    @Test func staleFinancialEditRefreshesTheSnapshotAndInvalidatesAnOutdatedRetry() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let action = "I review the website's plans."
        r.model.composer = action
        r.model.send()
        await r.model.turnTask?.value
        #expect(r.model.canRetry && r.model.failedTurn != nil)
        let captured = try #require(r.model.snapshot)
        try r.store.updateSettings(SessionSettings(), swingDial: 1, replyLengthWords: 500)
        let revision = try r.store.revision()
        let opening = AccountOpening(id: "website", name: "Website business", kind: .business)

        #expect(throws: ValidationError.self) {
            try r.model.updateFinances(accountOpenings: [opening], streamChanges: [], transfers: [],
                expectedLifeID: captured.character.id, expectedRevision: captured.revision)
        }

        let refreshed = try #require(r.model.snapshot)
        #expect(refreshed.revision == revision && refreshed.revision == captured.revision + 1)
        #expect(refreshed.character.replyLengthWords == 500)
        #expect(refreshed.accounts == captured.accounts)
        #expect(refreshed.messages == captured.messages && refreshed.character.currentDate == captured.character.currentDate)
        #expect(!r.model.canRetry && r.model.failedTurn == nil && r.model.validationDetails.isEmpty)
        #expect(r.model.composer == action)
        r.model.retryTurn()
        #expect(await r.narrator.requests.count == 2)
        #expect(try r.store.revision() == revision)

        // A reopened sheet uses the refreshed snapshot; the rejected draft was never applied.
        try r.model.updateFinances(accountOpenings: [opening], streamChanges: [], transfers: [],
            expectedLifeID: refreshed.character.id, expectedRevision: refreshed.revision)
        #expect(r.model.snapshot?.revision == revision + 1)
        #expect(r.model.snapshot?.accounts.filter { $0.id == "website" }.count == 1)
        #expect(try r.store.recentMessages(limit: 100) == captured.messages)
    }

    @Test(arguments: ["account", "income", "transfer"])
    func financialEditsInvalidatePendingRetry(_ edit: String) async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.paths.root) }
        let initial = try #require(r.model.snapshot)
        try r.model.updateFinances(
            accountOpenings: [AccountOpening(id: "website", name: "Website business", kind: .business)],
            streamChanges: [], transfers: [], expectedLifeID: initial.character.id, expectedRevision: initial.revision)
        let action = "I inspect the website's customer feedback."
        r.model.composer = action
        r.model.send()
        await r.model.turnTask?.value
        #expect(r.model.canRetry && r.model.failedTurn != nil)
        #expect(!r.model.validationDetails.isEmpty)
        #expect(await r.narrator.requests.count == 2)
        let before = try #require(r.model.snapshot)

        let openings = edit == "account" ? [AccountOpening(id: "savings", name: "Savings", kind: .savings)] : []
        let changes = edit == "income" ? [websiteIncome(date: before.character.currentDate)] : []
        let transfers = edit == "transfer" ? [AccountTransfer(fromAccount: "personal", toAccount: "website",
            amountMinor: 50_000, reason: "Move existing savings into the business.")] : []
        try r.model.updateFinances(accountOpenings: openings, streamChanges: changes, transfers: transfers,
            expectedLifeID: before.character.id, expectedRevision: before.revision)

        #expect(r.model.failedTurn == nil && !r.model.canRetry)
        #expect(r.model.validationDetails.isEmpty)
        #expect(r.model.composer == action)
        #expect(r.model.snapshot?.revision == before.revision + 1)
        #expect(r.model.snapshot?.messages == before.messages)
        #expect(r.model.snapshot?.character.currentDate == before.character.currentDate)
        r.model.retryTurn()
        #expect(await r.narrator.requests.count == 2)
        #expect(try r.store.revision() == before.revision + 1)
        #expect(try r.store.recentMessages(limit: 100) == before.messages)
    }

    private func websiteIncome(date: GameDate) -> IncomeStreamChange {
        IncomeStreamChange(action: .start, name: "Website profit", kind: .business, tier: nil,
            monthlyMinor: 5_000_000, accountId: "website", effectiveFrom: date.iso,
            reason: "Established subscriptions earn USD 50,000 net profit per month after business costs.")
    }

    private func character(name: String = "Richard") -> NewCharacter {
        NewCharacter(name: name, birthplace: "Texas, USA", birthYear: 1985, appearance: "Tall", startingAge: 18,
            background: nil, familyWealthTier: .wealthy)
    }

    private func rig() throws -> (model: AppModel, store: LifeStore, narrator: FinanceRetryNarrator, paths: AppPaths) {
        let paths = try AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("lifegpt-finances-\(UUID().uuidString)"))
        let library = try ChatLibrary(directory: paths.chats)
        let store = try library.createChat(character: character(), economy: .sampleUS2005).store
        try store.saveOpening("You review your plans for the website.", choices: ["I inspect the website."])
        let narrator = FinanceRetryNarrator()
        let model = AppModel(paths: paths, narratorFactory: { narrator })
        return (model, store, narrator, paths)
    }
}

private actor FinanceRetryNarrator: Narrator {
    private(set) var requests: [NarratorRequest] = []
    func narrate(_ request: NarratorRequest) async throws -> NarratorResult {
        requests.append(request)
        var resolution = Resolution(zoom: .scene, timeAdvance: request.requestedTime ?? TimeAdvance(unit: .days, amount: 0))
        if requests.count <= 2 { resolution.crimeAttempt = CrimeAttempt(reason: String(repeating: "x", count: 501)) }
        return NarratorResult(output: TurnOutput(resolution: resolution, narration: "A quiet scene continues."), inputTokens: 10, outputTokens: 20)
    }
    func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult { try await narrate(request) }
}
