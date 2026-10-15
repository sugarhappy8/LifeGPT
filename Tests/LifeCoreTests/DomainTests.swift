import Testing
@testable import LifeCore

@Suite struct DomainTests {
    @Test func startDateIsJan1OfBirthYearPlusAge() {
        let c = Character(from: NewCharacter(name: "Lena", birthplace: "Ohio, USA", birthYear: 1990,
                                             appearance: "tall", startingAge: 15, background: nil))
        #expect(c.currentDate == GameDate(year: 2005, month: 1, day: 1))
        #expect(c.birthDate == GameDate(year: 1990, month: 1, day: 1))
        #expect(c.ageYears == 15)
    }

    @Test func addingMonthsClampsToMonthEnd() {
        #expect(GameDate(year: 2024, month: 1, day: 31).adding(months: 1) == GameDate(year: 2024, month: 2, day: 29))
        #expect(GameDate(year: 2023, month: 12, day: 15).adding(months: 2) == GameDate(year: 2024, month: 2, day: 15))
    }

    @Test func daysSinceSpansLeapDay() {
        #expect(GameDate(year: 2024, month: 3, day: 1).daysSince(GameDate(year: 2024, month: 2, day: 1)) == 29)
        #expect(GameDate(year: 2024, month: 1, day: 1).adding(days: 366) == GameDate(year: 2025, month: 1, day: 1))
    }

    @Test func isoRoundTripsAndRejectsInvalid() {
        #expect(GameDate(iso: "2020-02-29") == GameDate(year: 2020, month: 2, day: 29))
        #expect(GameDate(year: 2020, month: 2, day: 9).iso == "2020-02-09")
        #expect(GameDate(iso: "2021-02-29") == nil)
        #expect(GameDate(iso: "garbage") == nil)
    }

    @Test func ageTurnsOverOnBirthday() {
        let born = GameDate(year: 2000, month: 6, day: 15)
        #expect(GameDate(year: 2018, month: 6, day: 14).ageYears(bornOn: born) == 17)
        #expect(GameDate(year: 2018, month: 6, day: 15).ageYears(bornOn: born) == 18)
    }

    @Test func formatsMoney() {
        #expect(Money.format(123_456, economy: .sampleUS2005) == "1,234.56 USD")
        #expect(Money.format(-500, economy: .sampleUS2005) == "-5.00 USD")
        #expect(Money.format(Int64.min, economy: .sampleUS2005).hasPrefix("-"))
    }

    @Test func startingBalanceScalesWithAge() {
        let e = EconomyCard.sampleUS2005
        #expect(StartingMoney.balanceMinor(forAge: 8, economy: e) == 7_000)
        #expect(StartingMoney.balanceMinor(forAge: 15, economy: e) == 35_000)
        #expect(StartingMoney.balanceMinor(forAge: 30, economy: e) == 175_000)
    }
}
