import Foundation

/// Saves each life as one JSON file under Application Support/LifeGPT/Saves. Writes are atomic,
/// so a crash mid-save never corrupts a life.
public struct SaveStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultStore() throws -> SaveStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return SaveStore(directory: base.appendingPathComponent("LifeGPT/Saves", isDirectory: true))
    }

    public func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    public func save(_ state: GameState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url(for: state.id), options: .atomic)
    }

    public func load(_ id: UUID) throws -> GameState {
        try Self.decode(Data(contentsOf: url(for: id)))
    }

    /// All readable saves, most recently played first. Unreadable files are skipped, not deleted.
    public func loadAll() -> [GameState] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decode(Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    static func decode(_ data: Data) throws -> GameState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GameState.self, from: data)
    }
}
