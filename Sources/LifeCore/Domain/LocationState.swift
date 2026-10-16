import Foundation

/// An authoritative, dated residence. Descriptive story text cannot replace it.
public struct ResidenceChange: Codable, Equatable, Sendable {
    public var jurisdiction: JurisdictionRef
    public var effectiveFrom: GameDate
    public var reason: String
    public init(jurisdiction: JurisdictionRef, effectiveFrom: GameDate, reason: String = "Residence updated") {
        self.jurisdiction = jurisdiction; self.effectiveFrom = effectiveFrom; self.reason = reason
    }
    enum CodingKeys: String, CodingKey { case jurisdiction, effectiveFrom, reason }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jurisdiction = try c.decode(JurisdictionRef.self, forKey: .jurisdiction)
        let raw = try c.decode(String.self, forKey: .effectiveFrom)
        guard let date = GameDate(iso: raw) else { throw ValidationError.invalid("Residence needs a valid YYYY-MM-DD date.") }
        effectiveFrom = date; reason = try c.decode(String.self, forKey: .reason)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jurisdiction, forKey: .jurisdiction); try c.encode(effectiveFrom.iso, forKey: .effectiveFrom)
        try c.encode(reason, forKey: .reason)
    }
}

public struct LifeGeography: Codable, Equatable, Sendable {
    public var birth: JurisdictionRef?
    public var residences: [ResidenceChange]
    public init(birth: JurisdictionRef? = nil, residences: [ResidenceChange] = []) {
        self.birth = birth; self.residences = residences
    }
    public func residence(on date: GameDate) -> JurisdictionRef? {
        residences.filter { $0.effectiveFrom <= date }.sorted { $0.effectiveFrom < $1.effectiveFrom }.last?.jurisdiction
    }
    public func applying(_ changes: [ResidenceChange], from start: GameDate, through end: GameDate) throws -> LifeGeography {
        guard changes.count <= 24 else { throw ValidationError.invalid("At most 24 residence changes may occur in a turn.") }
        var copy = self
        var dates = Set<GameDate>()
        for change in changes.sorted(by: { $0.effectiveFrom < $1.effectiveFrom }) {
            guard change.effectiveFrom >= start, change.effectiveFrom <= end,
                  dates.insert(change.effectiveFrom).inserted, !change.reason.isEmpty, change.reason.count <= 1000 else {
                throw ValidationError.invalid("Residence changes need distinct dates inside this turn and a concise reason.")
            }
            try CountryCatalog.shared.validate(change.jurisdiction, on: change.effectiveFrom)
            copy.residences.removeAll { $0.effectiveFrom == change.effectiveFrom }
            copy.residences.append(change)
        }
        copy.residences.sort { $0.effectiveFrom < $1.effectiveFrom }
        return copy
    }
}
