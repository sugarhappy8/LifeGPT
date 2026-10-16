import Foundation

/// Deterministic compaction preserves the original transcript and uses no extra API calls.
/// These extracts are context aids; structured facts always take precedence.
public enum MemoryCompactor {
    public static func compactIfNeeded(store: LifeStore) throws {
        let through = try store.chapters().last?.throughMessageID ?? 0
        let pending = try store.messages(after: through, limit: 80)
        guard pending.count >= 40 else { return }
        let batch = Array(pending.prefix(24))
        guard let last = batch.last else { return }
        let snippets = batch.map { message in
            let compact = message.text.replacingOccurrences(of: "\n", with: " ")
            return "\(message.date.iso) \(message.role == .player ? "Attempt" : "Scene"): \(compact.prefix(message.role == .player ? 200 : 500))"
        }
        try store.saveChapter(throughMessageID: last.id, date: last.date, text: snippets.joined(separator: "\n"))
    }
}
