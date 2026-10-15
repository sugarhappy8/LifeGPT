import AppKit
import SwiftUI

@main
struct LifeGPTApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Needed when launched as a bare SwiftPM binary (`swift run`); harmless inside the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("LifeGPT") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Life") { model.showingNewLife = true }
                    .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
