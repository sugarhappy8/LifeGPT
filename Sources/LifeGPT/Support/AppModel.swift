import Foundation
import LifeGPTCore
import SwiftUI

enum SettingsKeys {
    static let provider = "provider"
    static let model = "model"
}

@MainActor
final class AppModel: ObservableObject {
    @Published var saves: [GameState] = []
    @Published var selectedID: UUID?
    @Published var isWorking = false
    @Published var statusText = ""
    @Published var errorMessage: String?
    @Published var showingNewLife = false

    private let store: SaveStore

    init() {
        let store = (try? SaveStore.defaultStore()) ?? SaveStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("LifeGPT"))
        self.store = store
        saves = store.loadAll()
        selectedID = saves.first?.id
    }

    var selected: GameState? { saves.first { $0.id == selectedID } }

    var providerKind: ProviderKind {
        ProviderKind(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.provider) ?? "") ?? .anthropic
    }

    var model: String {
        let m = UserDefaults.standard.string(forKey: SettingsKeys.model) ?? ""
        return providerKind.models.contains(m) ? m : providerKind.defaultModel
    }

    var hasAPIKey: Bool { !(KeychainStore.apiKey(for: providerKind.rawValue) ?? "").isEmpty }

    private func makeEngine() throws -> GameEngine {
        guard let key = KeychainStore.apiKey(for: providerKind.rawValue), !key.isEmpty else { throw LifeGPTError.missingAPIKey }
        return GameEngine(provider: providerKind.makeProvider(apiKey: key, model: model), store: store)
    }

    func startLife(_ options: NewLifeOptions) async {
        let state = options.makeState()
        do {
            try store.save(state)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        upsert(state)
        selectedID = state.id
        showingNewLife = false
        await play(GameEngine.openingAction)
    }

    func play(_ action: String) async {
        guard let current = selected, !isWorking else { return }
        isWorking = true
        statusText = current.turns.isEmpty ? "Your story begins..." : "Living..."
        defer { isWorking = false; statusText = "" }
        do {
            let engine = try makeEngine()
            let (next, _) = try await engine.playTurn(action, on: current)
            upsert(next)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ id: UUID) {
        try? store.delete(id)
        saves.removeAll { $0.id == id }
        if selectedID == id { selectedID = saves.first?.id }
    }

    private func upsert(_ state: GameState) {
        if let i = saves.firstIndex(where: { $0.id == state.id }) {
            saves[i] = state
        } else {
            saves.insert(state, at: 0)
        }
    }
}
