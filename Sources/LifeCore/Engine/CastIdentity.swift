import Foundation

/// Resolve only unambiguous existing people; an unfamiliar giver still needs validation.
public enum CastIdentity {
    public static func resolve(_ name: String, in cast: [CastMember]) -> CastMember? {
        let key = normalized(name)
        guard !key.isEmpty else { return nil }
        let exact = cast.filter { normalized($0.name) == key }
        if exact.count == 1 { return exact[0] }
        let role = familyRole(key)
        let matches = cast.filter { person in
            if let role, familyRole(normalized(person.relation ?? "")) == role { return true }
            // A first or last name is safe only if exactly one saved person has it.
            return !key.contains(" ") && normalized(person.name).split(separator: " ").contains(Substring(key))
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
    private static func familyRole(_ value: String) -> String? {
        var words = value.split(separator: " ").map(String.init)
        if let first = words.first, ["my", "your", "his", "her", "their"].contains(first) { words.removeFirst() }
        let value = words.joined(separator: " ")
        for (role, aliases) in [
            "father": ["father", "dad", "daddy", "papa"],
            "mother": ["mother", "mom", "mum", "mommy", "mama"],
            "grandfather": ["grandfather", "grandpa"], "grandmother": ["grandmother", "grandma"],
            "brother": ["brother"], "sister": ["sister"], "uncle": ["uncle"], "aunt": ["aunt"],
            "husband": ["husband"], "wife": ["wife"]
        ] where aliases.contains(value) { return role }
        return nil
    }
}
