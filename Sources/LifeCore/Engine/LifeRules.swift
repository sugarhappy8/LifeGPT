import Foundation

public enum PlayStyle: String, Codable, CaseIterable, Sendable {
    case simulation, sandbox
    public var label: String { self == .simulation ? "Simulation" : "Sandbox" }
    public var explanation: String {
        self == .simulation
            ? "Actions face challenges; established businesses can grow beyond ordinary wage bands."
            : "Your declared fictional outcomes shape the story. Record their financial effects; keep balances, transfers and recurring payments consistent."
    }
}

public enum HouseholdSupport: String, Codable, CaseIterable, Sendable {
    case automatic
    case familySupported = "family_supported"
    case independent

    public var label: String {
        switch self {
        case .automatic: "Follow the story"
        case .familySupported: "Family covers rent and living costs"
        case .independent: "I pay my own living costs"
        }
    }

    /// Explicit settings win, then current household facts, then the starting background.
    /// Market prices are never changed by who pays the protagonist's bills.
    public static func resolve(settings: SessionSettings, state: [String: String], background: String?) -> Self {
        if settings.household != .automatic { return settings.household }
        if let value = state["household_support"], let support = Self(rawValue: value), support != .automatic { return support }
        let housing = ["residence", "living_arrangement", "housing", "home"].compactMap { state[$0] }.joined(separator: " ")
        if let inferred = infer(housing) { return inferred }
        return infer(background ?? "") ?? .independent
    }

    public static func infer(_ text: String) -> Self? {
        let text = text.lowercased().replacingOccurrences(of: "’", with: "'")
        // Explicit independence overrides royal origins or a reference to a former family home.
        if ["live independently", "living independently", "moved out", "pay my own rent",
            "pays their own rent", "no family support", "disowned", "no longer live with", "no longer living with"].contains(where: text.contains) { return .independent }
        if ["with my parents", "with your parents", "with his parents", "with her parents", "with their parents",
            "parents' home", "parents' house", "parent's home", "family home", "family covers", "family pays",
            "parents cover", "parents pay", "rent-free"].contains(where: text.contains) { return .familySupported }
        if StartingPremise.isRoyal(text) { return .familySupported }
        if ["own apartment", "rented room", "renting an apartment", "living alone", "living on my own"].contains(where: text.contains) { return .independent }
        return nil
    }

    public func monthlyCost(economy: EconomyCard) -> Int64 { self == .familySupported ? 0 : economy.monthlyLivingCostMinor }
}

public enum StartingPremise {
    /// Offline setup hints. The setup model also interprets free-form backgrounds semantically.
    public static func isRoyal(_ text: String) -> Bool {
        let text = text.lowercased()
        guard text.range(of: #"\b(not|non)[ -]royal\b|\bnot royalty\b"#, options: .regularExpression) == nil else { return false }
        return text.range(of: #"\b(royalty|royailty|royal family|royal household|royal prince|royal princess|crown prince|crown princess|ruling family)\b"#, options: .regularExpression) != nil
    }
}

public enum GameDifficulty {
    public static func modifier(_ difficulty: Int) -> Int { (50 - min(100, max(0, difficulty))) * 30 / 50 }
    public static func effectiveFate(_ raw: Int, difficulty: Int) -> Int {
        min(100, max(1, raw + modifier(difficulty)))
    }
    public static func label(_ difficulty: Int) -> String {
        switch difficulty {
        case ..<25: "Forgiving"
        case 25..<50: "Relaxed"
        case 50: "Balanced"
        case 51..<76: "Demanding"
        default: "Challenging"
        }
    }
    public static func direction(_ difficulty: Int) -> String {
        if difficulty < 50 {
            return "Favor the player's intended direction. Treat ambitious goals as achievable with established resources, collaborators and elapsed time. Reward effort and family access; allow breakthroughs and substantial audience growth. Do not reflexively shrink a target such as 100,000 daily users to a token success or portray ambition as dishonesty. Use the adjusted fate for uncertainty. Money still needs valid ledger sources and amounts."
        }
        if difficulty > 50 {
            return "Require stronger preparation for uncertain goals and show meaningful obstacles. Use the adjusted fate; let well-prepared actions succeed, without inventing punishment for ordinary scenes."
        }
        return "Balance opportunity and setbacks. Evaluate goals using preparation, resources, elapsed time and adjusted fate. Ambition alone is not a reason to fail; growth in audience or reputation is not a cash payout."
    }
}
