/// Source of the per-turn "fate dice": a number from 1 to 100 that the engine
/// rolls and hands to the narrator, so uncertain outcomes are not up to the AI.
public protocol FateSource: Sendable {
    mutating func roll() -> Int
}

/// Deterministic generator (SplitMix64) for reproducible runs.
public struct SeededFate: FateSource {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func roll() -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int(z % 100) + 1
    }
}

/// Cycles through fixed values; for tests and scripted demos.
public struct FixedFate: FateSource {
    private let values: [Int]
    private var index = 0

    public init(_ values: [Int]) {
        precondition(!values.isEmpty, "FixedFate needs at least one value")
        self.values = values
    }

    public mutating func roll() -> Int {
        defer { index = (index + 1) % values.count }
        return values[index]
    }
}
