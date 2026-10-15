import Foundation

public enum PlayerInput: Equatable, Sendable {
    /// What the character tries or says. Never a fact about the world.
    case attempt(String)
    /// A `((question))` to the game itself, answered from the database.
    case outOfCharacter(String)
    case empty
}

public enum IntentGuard {
    /// `((…))` is out-of-character only when it wraps the whole message exactly
    /// once; anything else, including malformed or mixed markers, is an attempt.
    public static func classify(_ raw: String) -> PlayerInput {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }

        if text.hasPrefix("(("), text.hasSuffix("))"), text.count >= 4 {
            let inner = String(text.dropFirst(2).dropLast(2))
            if !inner.contains("(("), !inner.contains("))") {
                let question = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                return question.isEmpty ? .empty : .outOfCharacter(question)
            }
        }
        return .attempt(text)
    }
}
