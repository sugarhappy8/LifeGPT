import Foundation

public enum ContinuityValidator {
    public struct Result {
        public var cast: [CastUpdate] = []
        public var state: [LifeStateChange] = []
        public var threads: [StoryThread] = []
        public var rejections: [String] = []
    }
    public static func validate(_ resolution: Resolution, truth: GroundTruth) -> Result {
        var result = Result()
        let uncanny = truth.character.swingDial >= 2 && resolution.events.contains(where: \.uncanny)
        for original in resolution.castUpdates.prefix(30) {
            var update = original
            update.name = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
            update.status = update.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !update.name.isEmpty else { continue }
            guard update.name.count <= 100, (update.notes?.count ?? 0) <= 4000,
                  update.status == nil || ["alive", "dead", "missing", "estranged"].contains(update.status!.lowercased()) else {
                result.rejections.append("cast: invalid name, notes or status for \(update.name)"); continue
            }
            let old = truth.cast.first { $0.name.caseInsensitiveCompare(update.name) == .orderedSame }
            if old?.status.lowercased() == "dead", let status = update.status, status != "dead", !uncanny {
                result.rejections.append("\(update.name) is dead and cannot return without an uncanny event at Swing Dial 2 or 3"); continue
            }
            result.cast.append(update)
        }
        let reserved = Set(["money", "balance", "age", "date", "birth_year", "birth_date", "family_wealth_tier", "currency"])
        for original in resolution.lifeStateChanges.prefix(30) {
            var state = original
            state.key = state.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
            guard !state.key.isEmpty, state.key.count <= 60, state.value.count <= 4000,
                  !reserved.contains(state.key.lowercased()), !state.key.hasPrefix("_engine_") else {
                result.rejections.append("life_state cannot override engine-owned facts: \(state.key)"); continue
            }
            if state.key == "household_support" {
                state.value = state.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard [.familySupported, .independent].contains(HouseholdSupport(rawValue: state.value)) else {
                    result.rejections.append("household_support must be family_supported or independent"); continue
                }
            }
            result.state.append(state)
        }
        for thread in (resolution.threadUpdates ?? []).prefix(12) {
            guard !thread.id.isEmpty, thread.id.count <= 100, !thread.title.isEmpty,
                  thread.title.count <= 200, thread.notes.count <= 2000 else {
                result.rejections.append("story thread needs a stable ID and concise title/notes"); continue
            }
            result.threads.append(thread)
        }
        if resolution.castUpdates.count > 30 || resolution.lifeStateChanges.count > 30 || (resolution.threadUpdates?.count ?? 0) > 12 {
            result.rejections.append("too many continuity changes in one turn")
        }
        return result
    }
}

/// A conservative local tripwire, alongside the provider's safety controls and the system policy.
/// It intentionally does not claim to classify all natural-language content.
public enum ContentGuard {
    public static func check(_ text: String, characterAge: Int) throws {
        let lower = text.lowercased()
        let sexual = #"\b(sex|sexual|porn|pornographic|nude|naked|erotic|intercourse|masturbat\w*|orgasm\w*|molest\w*)\b"#
        let minor = #"\b(child|children|minor|underage|preteen|toddler|schoolgirl|schoolboy|[1-9]|1[0-7])[- ]year[- ]old\b|\b(child|children|underage|preteen|toddler)\b"#
        if lower.range(of: sexual, options: .regularExpression) != nil,
           characterAge < 18 || lower.range(of: minor, options: .regularExpression) != nil {
            throw ValidationError.invalid("This scene cannot be played. Sexual content involving anyone under 18 is not allowed.")
        }
    }
}
