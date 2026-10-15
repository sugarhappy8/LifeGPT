import Foundation

public struct RenderedPrompt: Equatable, Sendable {
    public var system: String
    public var user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

/// Turns a `NarratorRequest` into the system prompt and user message, in the
/// order the outline's §6 gives. Player text is fenced and defanged so it can
/// only ever be read as an attempt.
public enum PromptRenderer {
    private static let systemText = resource("system")
    private static let voiceText = resource("voice")

    public static func render(_ request: NarratorRequest, rejections: [String] = []) -> RenderedPrompt {
        var user = groundTruthSection(request.groundTruth)
        user += "\n" + guardrailSection(request.groundTruth)
        user += "\n## THIS TURN\n"
        user += "Fate roll: \(request.fate)\n"
        user += "Target length: about \(request.targetWords) words\n"
        user += "Swing Dial: \(swingDial(request.groundTruth.character.swingDial))\n"

        if !request.recentMessages.isEmpty {
            user += "\n## RECENT TURNS (oldest first)\n"
            for message in request.recentMessages {
                user += "\(message.role == .player ? "Player" : "Narrator"): \(message.text)\n"
            }
        }
        if !rejections.isEmpty {
            user += "\n## REJECTED LAST TIME\n"
            user += rejections.map { "- \($0)" }.joined(separator: "\n")
            user += "\nFix these and return the complete JSON again.\n"
        }
        user += "\n## PLAYER ATTEMPT\n<player_attempt>\n\(defang(request.playerInput))\n</player_attempt>\n"

        return RenderedPrompt(system: systemText + "\n\n" + voiceText, user: user)
    }

    // MARK: Sections

    private static func groundTruthSection(_ t: GroundTruth) -> String {
        let c = t.character, e = t.economy
        func money(_ minor: Int64) -> String { Money.format(minor, economy: e) }

        var s = "## GROUND TRUTH (binding)\n"
        s += "Character: \(c.name), born \(c.birthYear) in \(c.birthplace). Appearance: \(c.appearance).\n"
        s += "Background: \(c.background ?? "none given")\n"
        s += "Family wealth tier: \(c.familyWealthTier.rawValue)\n"
        s += "Date: \(c.currentDate.iso). Age: \(c.ageYears).\n"
        s += "Balance: \(money(t.balanceMinor)) (\(t.balanceMinor) minor units)\n"
        s += "Currency: \(e.currency), \(e.minorUnitsPerUnit) minor units per unit.\n"

        let active = t.incomeStreams.filter { $0.endedOn == nil }
        s += "Income streams:"
        if active.isEmpty { s += " none\n" } else {
            s += "\n" + active.map {
                "- \($0.name): \(money($0.monthlyMinor)) per month (\($0.kind == .wage ? "wage" : "self-employment")\($0.tier.map { ", \($0)" } ?? ""))"
            }.joined(separator: "\n") + "\n"
        }

        s += "People:"
        if t.cast.isEmpty { s += " none yet\n" } else {
            s += "\n" + t.cast.map { member in
                var line = "- \(member.name)"
                var facts = [member.relation, member.status].compactMap { $0 }
                if let notes = member.notes { facts.append(notes) }
                if !facts.isEmpty { line += " (\(facts.joined(separator: ", ")))" }
                return line
            }.joined(separator: "\n") + "\n"
        }

        s += "Recent decisions (newest first):"
        if t.recentDecisions.isEmpty { s += " none yet\n" } else {
            s += "\n" + t.recentDecisions.map { "- \($0.date.iso): \($0.summary) (\($0.choice))" }
                .joined(separator: "\n") + "\n"
        }

        if !t.lifeState.isEmpty {
            s += "Life state:\n" + t.lifeState.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n") + "\n"
        }

        s += "Recent ledger (newest first):\n"
        s += t.recentLedger.map {
            "- \($0.date.iso) \($0.sourceType.rawValue) \($0.amountMinor >= 0 ? "+" : "")\($0.amountMinor): \($0.reason)"
        }.joined(separator: "\n") + "\n"
        return s
    }

    private static func guardrailSection(_ t: GroundTruth) -> String {
        let e = t.economy, g = t.guardrails
        func money(_ minor: Int64) -> String { "\(Money.format(minor, economy: e)) (\(minor) minor units)" }

        var s = "## GUARDRAILS\n"
        s += "- Side hustle or one-off sales (per 30 days): up to \(money(g.sideHustleCapMinor))\n"
        s += "- A gift from someone already in People: up to \(money(g.giftCapMinor)), and rarely from the same giver\n"
        s += "- A windfall needs a fate roll of \(g.windfallMinFate) or more, up to \(money(g.windfallCapMinor)), and is very rare\n"
        s += "- No single money entry may be larger than \(money(g.singleEntryBoundMinor))\n"
        s += "- Wage bands per month: " + e.wageBands.map {
            "\($0.name) \(Money.format($0.minMonthlyMinor, economy: e)) to \(Money.format($0.maxMonthlyMinor, economy: e))"
        }.joined(separator: "; ") + "\n"
        return s
    }

    private static func swingDial(_ level: Int) -> String {
        switch level {
        case 0: return "0 (Grounded) — plausible life, small turns"
        case 1: return "1 (Heightened) — dramatic coincidences and strong personalities"
        case 2: return "2 (Magical-realist) — quiet impossibilities treated as ordinary"
        default: return "3 (Surreal) — dream logic and genre shifts"
        }
    }

    /// Neutralizes every closing tag so player text cannot end its own fence.
    private static func defang(_ text: String) -> String {
        text.replacingOccurrences(of: "</", with: "<\\/")
    }

    private static func resource(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { preconditionFailure("missing prompt resource \(name).md") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
