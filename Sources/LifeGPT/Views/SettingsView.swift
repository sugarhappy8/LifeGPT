import LifeGPTCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(SettingsKeys.provider) private var providerRaw = ProviderKind.anthropic.rawValue
    @AppStorage(SettingsKeys.model) private var modelName = ProviderKind.anthropic.defaultModel
    @State private var apiKey = ""
    @State private var saved = false

    private var provider: ProviderKind { ProviderKind(rawValue: providerRaw) ?? .anthropic }

    var body: some View {
        Form {
            Picker("Provider", selection: $providerRaw) {
                ForEach(ProviderKind.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            Picker("Model", selection: $modelName) {
                ForEach(provider.models, id: \.self) { Text($0).tag($0) }
            }
            SecureField("API key", text: $apiKey, prompt: Text("Paste your key"))
            HStack {
                Button("Save Key") {
                    saved = KeychainStore.setAPIKey(apiKey, for: provider.rawValue)
                    model.objectWillChange.send()
                }
                if saved { Text("Saved to Keychain").foregroundStyle(.secondary) }
            }
            Text("Your key is stored only in this Mac's Keychain and is sent only to the provider you pick. Each turn is billed to your account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear(perform: loadKey)
        .onChange(of: providerRaw) {
            if !provider.models.contains(modelName) { modelName = provider.defaultModel }
            loadKey()
        }
    }

    private func loadKey() {
        apiKey = KeychainStore.apiKey(for: provider.rawValue) ?? ""
        saved = false
    }
}
