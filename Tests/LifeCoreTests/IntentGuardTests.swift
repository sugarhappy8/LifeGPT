import Testing
@testable import LifeCore

@Suite struct IntentGuardTests {
    @Test func classifiesPlayerInput() {
        #expect(IntentGuard.classify("  hello ") == .attempt("hello"))
        #expect(IntentGuard.classify("((what's my balance?))") == .outOfCharacter("what's my balance?"))
        #expect(IntentGuard.classify("  ((  hi  ))  ") == .outOfCharacter("hi"))
        #expect(IntentGuard.classify("(( ))") == .empty)
        #expect(IntentGuard.classify("(())") == .empty)
        #expect(IntentGuard.classify("   ") == .empty)
        #expect(IntentGuard.classify("") == .empty)
    }

    @Test func malformedOrMixedMarkersStayInCharacter() {
        #expect(IntentGuard.classify("((unclosed") == .attempt("((unclosed"))
        #expect(IntentGuard.classify("))((") == .attempt("))(("))
        #expect(IntentGuard.classify("((a)) and ((b))") == .attempt("((a)) and ((b))"))
        #expect(IntentGuard.classify("I whisper ((quietly))") == .attempt("I whisper ((quietly))"))
    }

    // MARK: Out-of-character answers (exact, from the database)

    private func chat() throws -> LifeStore {
        try TestChat.chat(try TestChat.library()).store   // Lena, age 30, 2020-01-01, balance 175_000
    }

    private func ask(_ q: String, _ store: LifeStore) throws -> String {
        try OOCResponder.answer(q, store: store)
    }

    @Test func answersBalanceAndDateExactly() throws {
        let store = try chat()
        #expect(try ask("what's my balance?", store) == "Balance: 1,750.00 USD")
        #expect(try ask("How much cash do I have", store) == "Balance: 1,750.00 USD")
        #expect(try ask("what is the date and how old am I", store) == "Date: 2020-01-01. Age: 30.")
    }

    @Test func answersIncome() throws {
        let store = try chat()
        #expect(try ask("what is my income?", store) == "No income streams.")
        let start = IncomeStreamChange(action: .start, name: "hardware store", kind: .wage, tier: "entry", monthlyMinor: 200_000)
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 2, day: 1), streamChanges: [start]))
        #expect(try ask("do I have a job", store) == "hardware store: 2,000.00 USD per month (wage), paid to personal")
        let quit = IncomeStreamChange(action: .end, name: "hardware store", kind: nil, tier: nil, monthlyMinor: nil)
        try store.apply(TestChat.turn(newDate: GameDate(year: 2020, month: 3, day: 1), streamChanges: [quit]))
        #expect(try ask("salary?", store) == "No income streams.")
    }

    @Test func answersPeople() throws {
        let store = try chat()
        #expect(try ask("who is in my life", store) == "People: none yet.")
        try store.apply(TestChat.turn(cast: [CastUpdate(name: "Maria", relation: "mother", notes: nil, status: nil),
                                             CastUpdate(name: "Joe", relation: nil, notes: nil, status: nil)]))
        #expect(try ask("list my family and friends", store) == "People: Maria (mother), Joe")
    }

    @Test func answersDecisions() throws {
        let store = try chat()
        #expect(try ask("what decisions have I made", store) == "Decisions: none yet.")
        try store.apply(TestChat.turn(decisions: [DecisionRecord(summary: "Took a job", choice: "hardware store", importance: .major)]))
        try store.apply(TestChat.turn(decisions: [DecisionRecord(summary: "Moved out", choice: "a small flat", importance: .major)]))
        #expect(try ask("my recent choices", store) == "Decisions: Moved out (a small flat); Took a job (hardware store)")
    }

    @Test func firstMatchingCategoryWinsAndUnknownGetsHelp() throws {
        let store = try chat()
        #expect(try ask("how old am I and what's my balance", store) == "Balance: 1,750.00 USD")
        #expect(try ask("tell me a joke", store)
                == "I can answer out-of-character questions about your balance, accounts, date and age, income, people, and decisions.")
    }
}
