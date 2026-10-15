import Foundation

/// A deterministic stand-in for the AI, so the whole loop can be exercised at
/// zero cost. It deliberately *obeys* huge money claims in the player's text,
/// which shows the engine rejecting them.
public struct MockNarrator: Narrator {
    public init() {}

    public func narrate(_ request: NarratorRequest) async throws -> NarratorResult {
        respond(to: request, obeyClaim: true)
    }

    public func repair(_ request: NarratorRequest, rejections: [String]) async throws -> NarratorResult {
        respond(to: request, obeyClaim: false)
    }

    private func respond(to request: NarratorRequest, obeyClaim: Bool) -> NarratorResult {
        let text = request.playerInput.lowercased()
        let economy = request.groundTruth.economy
        let passesAMonth = text.contains("month")
        let time = passesAMonth ? TimeAdvance(unit: .months, amount: 1) : TimeAdvance(unit: .days, amount: 0)
        let claim = Self.claimAmountMinor(in: text, minorUnitsPerUnit: economy.minorUnitsPerUnit)

        var money: [ProposedMoneyEntry] = []
        let narration: String
        if let claim, obeyClaim {
            money = [ProposedMoneyEntry(sourceType: .sideHustle, amountMinor: claim,
                                        reason: "sold spoons, as the player claimed")]
            narration = "Your spoons are the talk of the town: you made \(Money.format(claim, economy: economy))."
        } else if claim != nil || text.contains("sell") {
            let small: Int64 = 1_200
            money = [ProposedMoneyEntry(sourceType: .sideHustle, amountMinor: small,
                                        reason: "sold spoons at the market")]
            narration = "A few shoppers buy spoons at the market; you take home \(Money.format(small, economy: economy))."
        } else if passesAMonth {
            narration = "A month goes by."
        } else {
            narration = "The day passes quietly."
        }

        let resolution = Resolution(zoom: passesAMonth ? .summary : .scene, timeAdvance: time, money: money)
        return NarratorResult(output: TurnOutput(resolution: resolution, narration: narration),
                              inputTokens: 0, outputTokens: 0)
    }

    /// The size of a money claim in `text` ("200 million", "$1,000,000", a run
    /// of 6+ digits, or the bare word "million"/"billion"), in minor units.
    public static func claimAmountMinor(in text: String, minorUnitsPerUnit: Int) -> Int64? {
        let lower = text.lowercased()
        let units = Int64(max(minorUnitsPerUnit, 1))
        func minor(_ whole: Int64, _ multiplier: Int64) -> Int64 {
            MoneyRules.multiply(MoneyRules.multiply(whole, multiplier), units)
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d[\d,]*)(?:\s*(million|billion))?"#) {
            let ns = lower as NSString
            for match in regex.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
                let digits = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                var multiplier: Int64 = 1
                if match.range(at: 2).location != NSNotFound {
                    multiplier = ns.substring(with: match.range(at: 2)) == "billion" ? 1_000_000_000 : 1_000_000
                }
                if multiplier == 1 && digits.count < 6 { continue }
                guard let whole = Int64(digits) else { return Int64.max }
                return minor(whole, multiplier)
            }
        }
        if lower.contains("billion") { return minor(1, 1_000_000_000) }
        if lower.contains("million") { return minor(1, 1_000_000) }
        return nil
    }
}
