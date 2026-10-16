import Foundation

/// Current records are binding; historical prose is supporting evidence only.
enum SimulationContext {
    static func render(store: LifeStore, geography: LifeGeography) throws -> String {
        let date = try store.character().currentDate, economy = try store.economy()
        let state = try store.businessSimulation()
        let obligations = state.obligations.filter { $0.endedOn == nil || $0.endedOn! > date }
        let businesses = state.businesses.filter { $0.status == .active }
        var lines = ["CURRENT SIMULATION — \(date.iso). These saved records override earlier narration.",
            "Nation catalog: \(CountryCatalog.shared.version). country_id is an ISO alpha-2 preset ID; subdivision_id is its exact catalog ID (e.g. US-TX, AE-DU). Unknown or invented IDs are rejected.",
            "Default personal account: \(state.defaultPersonalAccountId). Only accounts marked accessible may be spent, transferred, managed, or counted as player cash.",
            "Geography: \(try json(geography))",
            "Active businesses: \(try json(businesses))",
            "Current/future recurring obligations: \(try json(obligations))",
            "Unpaid obligations: \(try json(state.payables.filter { $0.remainingMinor > 0 }))",
            "Partial-month accrued amounts awaiting settlement: \(try json(state.accruals))",
            "Financial positions (account permissions still apply): \(try json(store.positions()))",
            "Pending sale reviews (unconfirmed, no proceeds paid): \(try json(state.saleDrafts.filter { $0.confirmedOn == nil }))"]
        var profiles = Set<DatedJurisdiction>()
        func include(_ jurisdiction: JurisdictionRef?, on ruleDate: GameDate) {
            guard let jurisdiction else { return }
            // Locality is descriptive; it cannot create another fiscal jurisdiction.
            let canonical = JurisdictionRef(countryID: jurisdiction.countryID, subdivisionID: jurisdiction.subdivisionID)
            profiles.insert(DatedJurisdiction(jurisdiction: canonical, date: ruleDate))
        }
        include(geography.residence(on: date), on: date)
        for business in businesses {
            let applicableDate = max(date, business.openedOn)
            include(business.jurisdiction(on: applicableDate), on: applicableDate)
        }
        for obligation in obligations {
            let applicableDate = max(date, obligation.effectiveFrom)
            let business = businesses.first { $0.id == obligation.businessId }
            include(obligation.jurisdiction ?? business?.jurisdiction(on: applicableDate), on: applicableDate)
            include(obligation.taxResidence, on: applicableDate)
        }
        // Unsettled earnings can still use a prior month's rules or an earlier
        // override. Preserve those dates rather than substituting today's rates.
        for accrual in state.accruals {
            include(accrual.businessJurisdiction, on: accrual.ruleDate)
            include(accrual.obligation.jurisdiction, on: accrual.ruleDate)
            include(accrual.obligation.taxResidence, on: accrual.ruleDate)
        }
        for reference in profiles.sorted(by: {
            let a = $0.jurisdiction.countryID + ":" + ($0.jurisdiction.subdivisionID ?? "")
            let b = $1.jurisdiction.countryID + ":" + ($1.jurisdiction.subdivisionID ?? "")
            return a == b ? $0.date < $1.date : a < b
        }) {
            do {
                let profile = try BusinessEngine.profile(reference.jurisdiction, on: reference.date, economy: economy, state: state)
                lines.append("Applicable fiscal profile: \(try json(profile))")
            } catch {
                lines.append("Jurisdiction requires selection/review: \(reference.jurisdiction.countryID) as of \(reference.date.iso). \(error.localizedDescription). Do not invent missing rules.")
            }
        }
        if profiles.isEmpty { lines.append("Legacy residence unresolved: ask for a preset country/region before creating taxable business records. Existing net-income payments are preserved.") }
        lines.append("Revenue/payroll/expenses accrue from their effective dates and settle monthly in arrears. Owner salary is funded by company cash, net of withholding. Never duplicate these as income_streams or money. A sale proposal only prepares review; only explicit desktop confirmation completes a sale.")
        return lines.joined(separator: "\n")
    }
    private struct DatedJurisdiction: Hashable {
        var jurisdiction: JurisdictionRef
        var date: GameDate
    }
    private static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
