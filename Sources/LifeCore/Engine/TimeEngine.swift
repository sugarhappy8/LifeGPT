/// Turns elapsed time into money: wages and living costs on each 1st of the
/// month. Pure, so a turn can be previewed before anything is written.
public enum TimeEngine {
    static let adultAge = 18

    /// Ledger entries (origin `.engine`) for every 1st of a month in
    /// `(character.currentDate, character.currentDate + days]`. Streams pay
    /// from the day they start until the day they end (exclusive).
    public static func plan(days: Int, character: Character, streams: [IncomeStream],
                            economy: EconomyCard) -> [NewLedgerEntry] {
        guard days > 0 else { return [] }
        let end = character.currentDate.adding(days: days)
        var boundary = firstOfNextMonth(after: character.currentDate)
        var entries: [NewLedgerEntry] = []

        while boundary <= end {
            for stream in streams where isActive(stream, on: boundary) {
                switch stream.kind {
                case .wage:
                    entries.append(NewLedgerEntry(date: boundary, sourceType: .wage,
                                                  amountMinor: stream.monthlyMinor,
                                                  reason: "Pay from \(stream.name)",
                                                  counterparty: nil, origin: .engine))
                case .selfEmployment:
                    entries.append(NewLedgerEntry(date: boundary, sourceType: .sideHustle,
                                                  amountMinor: stream.monthlyMinor,
                                                  reason: "Income from \(stream.name)",
                                                  counterparty: nil, origin: .engine))
                }
            }
            if boundary.ageYears(bornOn: character.birthDate) >= adultAge {
                entries.append(NewLedgerEntry(date: boundary, sourceType: .livingCost,
                                              amountMinor: -economy.monthlyLivingCostMinor,
                                              reason: "Rent and living costs",
                                              counterparty: nil, origin: .engine))
            }
            boundary = boundary.adding(months: 1)
        }
        return entries
    }

    private static func isActive(_ stream: IncomeStream, on date: GameDate) -> Bool {
        guard stream.startedOn <= date else { return false }
        if let ended = stream.endedOn { return date < ended }
        return true
    }

    private static func firstOfNextMonth(after date: GameDate) -> GameDate {
        GameDate(year: date.year, month: date.month, day: 1).adding(months: 1)
    }
}
