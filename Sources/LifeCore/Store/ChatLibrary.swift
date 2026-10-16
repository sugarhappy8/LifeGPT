import Foundation

public struct ChatSummary: Equatable, Sendable {
    public var id: UUID
    public var characterName: String
    public var currentDate: GameDate
    public var ageYears: Int
    public var lastPlayed: Date

    public init(id: UUID, characterName: String, currentDate: GameDate, ageYears: Int, lastPlayed: Date) {
        self.id = id
        self.characterName = characterName
        self.currentDate = currentDate
        self.ageYears = ageYears
        self.lastPlayed = lastPlayed
    }
}

/// The folder of chats. Each chat is one `<uuid>.lifechat` file and shares
/// nothing with any other.
public final class ChatLibrary: Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).lifechat")
    }

    public func createChat(character: NewCharacter, economy: EconomyCard) throws -> (id: UUID, store: LifeStore) {
        let id = UUID()
        let store = try LifeStore.create(at: fileURL(for: id), character: character, economy: economy, id: id)
        return (id, store)
    }

    public func openChat(id: UUID) throws -> LifeStore {
        try LifeStore.open(at: fileURL(for: id))
    }

    /// Chats that can be read, most recently played first. Files that are not
    /// valid chats (corrupt, or from a newer version) are skipped.
    public func list() throws -> [ChatSummary] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var summaries: [ChatSummary] = []
        for file in files where file.pathExtension == "lifechat" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let store = try? LifeStore.open(at: file),
                  let character = try? store.character(),
                  let lastPlayed = try? store.lastPlayed()
            else { continue }
            summaries.append(ChatSummary(id: id, characterName: character.name,
                                         currentDate: character.currentDate,
                                         ageYears: character.ageYears, lastPlayed: lastPlayed))
        }
        return summaries.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    /// Removes the chat's file and any SQLite sidecar files.
    public func deleteChat(id: UUID) throws {
        let file = fileURL(for: id)
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let url = URL(fileURLWithPath: file.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}

extension ChatLibrary {
    public func importChat(from source: URL) throws -> UUID {
        let id = UUID()
        do {
            try LifeStore.copyForImport(from: source, to: fileURL(for: id))
            let imported = try openChat(id: id)
            _ = try imported.character()
            try imported.economy().validate()
            _ = try imported.positions()
            try imported.assignIdentity(id)
            return id
        } catch { try? deleteChat(id: id); throw error }
    }

    public func unreadableFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lifechat" }
            .compactMap { file in
                do {
                    guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else {
                        return file.lastPathComponent + ": unexpected filename; use Import Life to add it."
                    }
                    _ = try LifeStore.open(at: file).character()
                    return nil
                } catch { return file.lastPathComponent + ": " + error.localizedDescription }
            }
    }
}
