import Foundation
import GRDB

extension LifeStore {
    public func businessSimulation() throws -> BusinessSimulationState {
        try dbQueue.read { try Self.simulationRecord($0, key: "business", default: BusinessSimulationState()) }
    }

    /// Legacy location strings are interpreted only when a preset matches unambiguously.
    /// This read does not rewrite an old save or infer historical financial transactions.
    public func geography() throws -> LifeGeography {
        try dbQueue.read { db in
            if let json = try String.fetchOne(db, sql: "SELECT json FROM simulation_records WHERE key = 'geography'") {
                return try JSONDecoder().decode(LifeGeography.self, from: Data(json.utf8))
            }
            guard let row = try Row.fetchOne(db, sql: "SELECT birthplace, birth_date, game_date FROM character") else { return LifeGeography() }
            let birth = try Self.parseDate(row["birth_date"]), date = try Self.parseDate(row["game_date"])
            let birthplace: String = row["birthplace"]
            let location = try String.fetchOne(db, sql: "SELECT value FROM life_state WHERE key = 'residence'")
                ?? String.fetchOne(db, sql: "SELECT location FROM place_time_brief ORDER BY version DESC LIMIT 1") ?? birthplace
            let current = CountryCatalog.shared.resolveLegacy(location, on: date)
            return LifeGeography(birth: CountryCatalog.shared.resolveLegacy(birthplace, on: birth),
                residences: current.map { [ResidenceChange(jurisdiction: $0, effectiveFrom: date, reason: "Matched legacy location; no past tax assumptions")] } ?? [])
        }
    }

    static func simulationRecord<T: Decodable>(_ db: Database, key: String, default fallback: T) throws -> T {
        guard let json = try String.fetchOne(db, sql: "SELECT json FROM simulation_records WHERE key = ?", arguments: [key]) else { return fallback }
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func writeSimulationRecord<T: Encodable>(_ db: Database, key: String, value: T) throws {
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        try db.execute(sql: "INSERT INTO simulation_records (key, json) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET json = excluded.json", arguments: [key, json])
    }

    static func writeGeography(_ db: Database, geography: LifeGeography, date: GameDate) throws {
        try writeSimulationRecord(db, key: "geography", value: geography)
        guard let residence = geography.residence(on: date) else { return }
        let location = CountryCatalog.shared.displayName(residence, on: date)
        let old = try String.fetchOne(db, sql: "SELECT value FROM life_state WHERE key = 'residence'")
        if old != location {
            try db.execute(sql: "INSERT INTO life_state_history (date, key, value) VALUES (?, 'residence', ?)", arguments: [date.iso, location])
            try db.execute(sql: "INSERT INTO life_state (key, value) VALUES ('residence', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [location])
        }
    }

    static func syncAccountNames(_ db: Database, state: BusinessSimulationState) throws {
        for account in state.accountMetadata {
            try db.execute(sql: "UPDATE accounts SET name = ? WHERE id = ? AND name != ?", arguments: [account.name, account.id, account.name])
        }
    }

    /// Manual finance edits use exactly the same engine and optimistic transaction as narration.
    public func updateBusinessSimulation(businessChanges: [BusinessChange] = [], obligationChanges: [ObligationChange] = [],
                                        accountChanges: [AccountLifecycleChange] = [], saleProposals: [SaleProposal] = [],
                                        convertLegacyIncome: Bool = false, expectedRevision: Int) throws {
        guard try revision() == expectedRevision, !(try hasEnded()) else { throw ValidationError.invalid("This life changed or ended. Reopen its finances.") }
        let date = try character().currentDate
        try validateAccountClosures(accountChanges)
        try validateSaleRetentions(saleProposals)
        let accountIDs = Set(businessChanges.filter { $0.action == .create }.compactMap(\.accountId))
        let legacy = try incomeStreams().filter { $0.endedOn == nil && accountIDs.contains($0.accountId) }
        guard legacy.isEmpty || convertLegacyIncome else {
            throw ValidationError.invalid("This account already receives legacy net income. Explicitly convert it from today's date before enabling gross accounting.")
        }
        let endings = legacy.map { IncomeStreamChange(action: .end, name: $0.name, kind: nil, tier: nil, monthlyMinor: nil, effectiveFrom: date.iso) }
        let plan = try BusinessEngine.prepare(state: businessSimulation(), accounts: accounts(), start: date, end: date,
            economy: economy(), businessChanges: businessChanges, obligationChanges: obligationChanges,
            accountChanges: accountChanges, saleProposals: saleProposals, revision: expectedRevision + 1)
        guard plan.rejections.isEmpty else { throw ValidationError.invalid(plan.rejections.joined(separator: "\n")) }
        try commitBusinessPlan(plan, expectedRevision: expectedRevision, title: "Business records updated", streamChanges: endings)
    }

    public func confirmBusinessSale(id: String, expectedRevision: Int) throws {
        guard try revision() == expectedRevision, !(try hasEnded()) else { throw ValidationError.invalid("This life changed or ended. Review the sale again.") }
        let plan = try BusinessEngine.confirmSale(id: id, expectedRevision: expectedRevision, currentRevision: revision(),
            state: businessSimulation(), accounts: accounts(), date: character().currentDate, economy: economy())
        guard plan.rejections.isEmpty else { throw ValidationError.invalid(plan.rejections.joined(separator: "\n")) }
        let draft = plan.state.saleDrafts.first { $0.id == id }!
        try validateSaleRetentions([draft.proposal])
        let endings = try incomeStreams().filter { $0.endedOn == nil && draft.transferredAccountIds.contains($0.accountId) }.map {
            IncomeStreamChange(action: .end, name: $0.name, kind: nil, tier: nil, monthlyMinor: nil,
                effectiveFrom: draft.proposal.effectiveFrom, reason: "Company ownership transferred")
        }
        try commitBusinessPlan(plan, expectedRevision: expectedRevision, title: "Company sale confirmed", streamChanges: endings,
            retainedLiabilities: draft.proposal.retainedLiabilityIds ?? [], liabilityAccount: draft.proposal.destinationAccountId)
    }

    public func updateFiscalOverride(jurisdiction: JurisdictionRef, values: FiscalOverrides, expectedRevision: Int) throws {
        guard try revision() == expectedRevision, !(try hasEnded()) else { throw ValidationError.invalid("Reopen the tax profile for the current save revision.") }
        let date = try character().currentDate
        let updated = try BusinessEngine.applyingFiscalOverride(BusinessFiscalOverride(jurisdiction: jurisdiction, effectiveFrom: date, values: values),
            to: businessSimulation(), at: date, economy: economy())
        try dbQueue.write { db in
            guard try Int.fetchOne(db, sql: "SELECT revision FROM session") == expectedRevision else { throw ValidationError.invalid("This life changed during the edit.") }
            try Self.writeSimulationRecord(db, key: "business", value: updated)
            try db.execute(sql: "UPDATE session SET revision = revision + 1")
        }
    }

    func validateSaleRetentions(_ proposals: [SaleProposal]) throws {
        let positions = try positions(), accounts = try accounts()
        for proposal in proposals {
            let ids = proposal.retainedLiabilityIds ?? []
            guard ids.count <= 200, Set(ids).count == ids.count else { throw ValidationError.invalid("Retained liabilities need unique recorded debt IDs.") }
            for id in ids {
                guard let position = positions.first(where: { $0.id == id }), position.isDebt, position.principalMinor > 0,
                      accounts.contains(where: { $0.id == (position.accountId ?? "personal") && $0.businessId == proposal.businessId && $0.isAccessible }) else {
                    throw ValidationError.invalid("A retained liability must be a recorded debt belonging to the company being sold.")
                }
            }
        }
    }

    func validateAccountClosures(_ changes: [AccountLifecycleChange], incomeChanges: [IncomeStreamChange] = []) throws {
        let positions = try positions(), income = try incomeStreams()
        for change in changes where change.action == .close {
            guard !positions.contains(where: { ($0.accountId ?? "personal") == change.accountId && $0.principalMinor > 0 }),
                  !income.contains(where: { stream in
                    stream.accountId == change.accountId && stream.endedOn == nil &&
                    !incomeChanges.contains(where: { $0.name == stream.name && $0.action == .end })
                  }) else {
                throw ValidationError.invalid("Resolve assets, loans, and legacy income linked to this account before closing it.")
            }
        }
    }

    private func commitBusinessPlan(_ plan: BusinessEngine.Plan, expectedRevision: Int, title: String, streamChanges: [IncomeStreamChange] = [], retainedLiabilities: [String] = [], liabilityAccount: String? = nil) throws {
        try dbQueue.write { db in
            guard try Int.fetchOne(db, sql: "SELECT revision FROM session") == expectedRevision else {
                throw ValidationError.invalid("This life changed during the edit. Reopen its finances.")
            }
            let date = try Self.parseDate(String.fetchOne(db, sql: "SELECT game_date FROM character") ?? "")
            try Self.writeFinances(db, accountOpenings: plan.accountOpenings, streamChanges: streamChanges, ledger: plan.ledger, through: date)
            try Self.writeSimulationRecord(db, key: "business", value: plan.state)
            try Self.syncAccountNames(db, state: plan.state)
            if let liabilityAccount {
                for id in retainedLiabilities {
                    guard let json = try String.fetchOne(db, sql: "SELECT json FROM financial_positions WHERE id = ?", arguments: [id]) else { throw ValidationError.invalid("A retained liability is missing.") }
                    var position = try JSONDecoder().decode(FinancialPosition.self, from: Data(json.utf8))
                    position.accountId = liabilityAccount
                    try db.execute(sql: "UPDATE financial_positions SET json = ? WHERE id = ?", arguments: [try Self.json(position), id])
                }
            }
            try db.execute(sql: "INSERT INTO events (date, title, importance, uncanny) VALUES (?, ?, 'major', 0)", arguments: [date.iso, title])
            try db.execute(sql: "UPDATE session SET revision = revision + 1, last_played = ?", arguments: [Date().timeIntervalSince1970])
        }
    }
}
