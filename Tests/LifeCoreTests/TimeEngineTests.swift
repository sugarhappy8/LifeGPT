import Testing
@testable import LifeCore

private func character(birthYear: Int, on date: GameDate) -> Character {
    var c = Character(from: NewCharacter(name: "Lena", birthplace: "Ohio, USA", birthYear: birthYear,
                                         appearance: "tall", startingAge: 0, background: nil))
    c.currentDate = date
    return c
}

private func wage(_ amount: Int64 = 200_000, started: GameDate = GameDate(year: 2000, month: 1, day: 1),
                  ended: GameDate? = nil, kind: IncomeStream.Kind = .wage) -> IncomeStream {
    IncomeStream(name: "shop", kind: kind, tier: "entry", monthlyMinor: amount, startedOn: started, endedOn: ended)
}

@Suite struct TimeEngineTests {
    @Test func seededFateIsDeterministicAndInRange() {
        var a = SeededFate(seed: 7), b = SeededFate(seed: 7), c = SeededFate(seed: 8)
        let first = (0..<50).map { _ in a.roll() }
        #expect(first == (0..<50).map { _ in b.roll() })
        #expect(first.allSatisfy { (1...100).contains($0) })
        #expect(first != (0..<50).map { _ in c.roll() })
        #expect(Set(first).count > 10)
    }

    @Test func fixedFateCycles() {
        var f = FixedFate([5, 95])
        #expect([f.roll(), f.roll(), f.roll()] == [5, 95, 5])
    }

    @Test func paysWagesAndChargesLivingCostAtMonthStarts() {
        let c = character(birthYear: 1990, on: GameDate(year: 2020, month: 1, day: 15))
        let entries = TimeEngine.plan(days: 60, character: c, streams: [wage()], economy: .sampleUS2005)
        let feb = GameDate(year: 2020, month: 2, day: 1), mar = GameDate(year: 2020, month: 3, day: 1)
        #expect(entries.map(\.date) == [feb, feb, mar, mar])
        #expect(entries.map(\.sourceType) == [.wage, .livingCost, .wage, .livingCost])
        #expect(entries.map(\.amountMinor) == [200_000, -120_000, 200_000, -120_000])
        #expect(entries.allSatisfy { $0.origin == .engine })
    }

    @Test func minorsPayNoLivingCosts() {
        let c = character(birthYear: 2003, on: GameDate(year: 2020, month: 1, day: 15))
        let entries = TimeEngine.plan(days: 60, character: c, streams: [wage()], economy: .sampleUS2005)
        #expect(entries.map(\.sourceType) == [.wage, .wage])
    }

    @Test func turningEighteenMidAdvanceStartsLivingCosts() {
        let c = character(birthYear: 2000, on: GameDate(year: 2017, month: 11, day: 15))
        let entries = TimeEngine.plan(days: 90, character: c, streams: [], economy: .sampleUS2005)
        #expect(entries.map(\.sourceType) == [.livingCost, .livingCost])
        #expect(entries.map(\.date) == [GameDate(year: 2018, month: 1, day: 1), GameDate(year: 2018, month: 2, day: 1)])
    }

    @Test func leapDayAndYearBoundary() {
        let leap = character(birthYear: 1990, on: GameDate(year: 2024, month: 2, day: 15))
        let a = TimeEngine.plan(days: 30, character: leap, streams: [wage()], economy: .sampleUS2005)
        #expect(a.filter { $0.sourceType == .wage }.map(\.date) == [GameDate(year: 2024, month: 3, day: 1)])
        let year = character(birthYear: 1990, on: GameDate(year: 2019, month: 12, day: 20))
        let b = TimeEngine.plan(days: 20, character: year, streams: [wage()], economy: .sampleUS2005)
        #expect(b.filter { $0.sourceType == .wage }.map(\.date) == [GameDate(year: 2020, month: 1, day: 1)])
    }

    @Test func endedAndFutureStreamsPayOnlyWhileActive() {
        let c = character(birthYear: 1990, on: GameDate(year: 2020, month: 1, day: 15))
        let ended = wage(ended: GameDate(year: 2020, month: 2, day: 10))
        let later = wage(300_000, started: GameDate(year: 2020, month: 2, day: 20))
        let entries = TimeEngine.plan(days: 60, character: c, streams: [ended, later], economy: .sampleUS2005)
        let pay = entries.filter { $0.sourceType == .wage }
        #expect(pay.map(\.date) == [GameDate(year: 2020, month: 2, day: 1), GameDate(year: 2020, month: 3, day: 1)])
        #expect(pay.map(\.amountMinor) == [200_000, 300_000])
    }

    @Test func selfEmploymentPaysAsSideHustle() {
        let c = character(birthYear: 1990, on: GameDate(year: 2020, month: 1, day: 15))
        let entries = TimeEngine.plan(days: 30, character: c, streams: [wage(100_000, kind: .selfEmployment)],
                                      economy: .sampleUS2005)
        #expect(entries.first?.sourceType == .sideHustle)
    }

    @Test func zeroOrNegativeDaysPlanNothing() {
        let c = character(birthYear: 1990, on: GameDate(year: 2020, month: 1, day: 15))
        #expect(TimeEngine.plan(days: 0, character: c, streams: [wage()], economy: .sampleUS2005).isEmpty)
        #expect(TimeEngine.plan(days: -5, character: c, streams: [wage()], economy: .sampleUS2005).isEmpty)
    }
}
