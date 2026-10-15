import LifeGPTCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingInspector = true

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                Section("Lives") {
                    ForEach(model.saves) { save in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(save.character.name).font(.headline)
                            Text(save.isDead ? "Died at \(save.age)" : "Age \(save.age) · \(save.world.currentDate.description)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(save.id)
                        .contextMenu {
                            Button("Delete Life", role: .destructive) { model.delete(save.id) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button { model.showingNewLife = true } label: { Label("New Life", systemImage: "plus") }
                }
            }
        } detail: {
            if let state = model.selected {
                GameView(state: state)
                    .inspector(isPresented: $showingInspector) {
                        LifePanel(state: state)
                            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                    }
                    .toolbar {
                        ToolbarItem {
                            Button { showingInspector.toggle() } label: { Label("Life Details", systemImage: "sidebar.right") }
                        }
                    }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $model.showingNewLife) {
            NewLifeView().environmentObject(model)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Text("LifeGPT").font(.system(size: 40, weight: .bold, design: .serif))
            Text("Live a whole life, one choice at a time. The AI narrates; your saved life is the memory.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if !model.hasAPIKey {
                SettingsLink { Text("Add your API key in Settings") }
            }
            Button("Start a New Life") { model.showingNewLife = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
    }
}
