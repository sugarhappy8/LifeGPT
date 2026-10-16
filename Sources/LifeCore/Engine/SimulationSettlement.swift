import Foundation

/// Interleaves company settlement with personal bills at each month boundary.
/// This is essential: a salary earned in January can pay February's personal bills.
enum SimulationSettlement {
    struct Result {
        var economy: EconomyCard
        var business: BusinessSimulationState
        var accounts: [BankAccount]
        var finances: FinanceEngine.Plan
        var openings: [AccountOpening]
        var rejections: [String]
    }

    static func run(prepared: BusinessEngine.Plan, character: Character, end: GameDate,
                    streams: [IncomeStream], economy: EconomyCard, positions: [FinancialPosition],
                    paths: [OpportunityPath], household: HouseholdSupport, geography: LifeGeography? = nil, originalResidence: JurisdictionRef? = nil) throws -> Result {
        var business = prepared.state
        var accounts = prepared.accounts
        var holdings = positions
        var ledger = prepared.ledger
        var openings = prepared.accountOpenings
        var rejections = prepared.rejections
        var cursor = character.currentDate
        var currentEconomy = economy
        let initialResidence = originalResidence
        func economyAt(_ date: GameDate) throws -> EconomyCard {
            guard let residence = geography?.residence(on: date),
                  residence.countryID != initialResidence?.countryID || residence.subdivisionID != initialResidence?.subdivisionID else { return economy }
            let override = business.fiscalOverrides.filter { $0.jurisdiction.countryID == residence.countryID && $0.jurisdiction.subdivisionID == residence.subdivisionID && $0.effectiveFrom <= date }
                .sorted { $0.effectiveFrom < $1.effectiveFrom }.last?.values
            return try CountryCatalog.shared.accountingEconomy(for: residence, on: date, accountingCurrency: economy.currency,
                minorUnitsPerUnit: economy.minorUnitsPerUnit, overrides: override)
        }
        var financial = FinanceEngine.Plan(positions: holdings, balance: 0,
            accountBalances: Dictionary(uniqueKeysWithValues: accounts.filter(\.isAccessible).map { ($0.id, $0.balanceMinor) }),
            personalAccountId: business.defaultPersonalAccountId)
        repeat {
            let boundary = GameDate(year: cursor.year, month: cursor.month, day: 1).adding(months: 1)
            let next = min(boundary, end)
            let step = try BusinessEngine.settle(state: business, accounts: accounts, from: cursor, to: next, economy: economy)
            business = step.state; accounts = step.accounts; ledger += step.ledger
            openings += step.accountOpenings; rejections += step.rejections
            currentEconomy = try economyAt(next)
            var segment = character; segment.currentDate = cursor
            let managedAccounts = Set(business.businesses.filter { $0.openedOn <= next }.map(\.accountId))
            let availableStreams = streams.filter { !managedAccounts.contains($0.accountId) }
            let activePaths = paths.filter { path in
                !business.businesses.contains { $0.openedOn <= next && ($0.id == path.id || $0.name.caseInsensitiveCompare(path.title) == .orderedSame) }
            }
            financial = try FinanceEngine.settle(to: next, character: segment, streams: availableStreams,
                economy: currentEconomy, balance: 0, positions: holdings, paths: activePaths, household: household,
                accounts: accounts, personalAccountId: business.defaultPersonalAccountId)
            ledger += financial.ledger; rejections += financial.rejections; holdings = financial.positions
            accounts = accounts.map { account in
                var copy = account
                if let cash = financial.accountBalances[account.id] { copy.balanceMinor = cash }
                return copy
            }
            cursor = next
        } while cursor < end
        financial.ledger = ledger
        financial.rejections = rejections
        return Result(economy: currentEconomy, business: business, accounts: accounts, finances: financial, openings: openings, rejections: rejections)
    }
}
