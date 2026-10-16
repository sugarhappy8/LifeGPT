import SwiftUI
import AppKit

@main
struct LifeGPTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    var body: some Scene {
        Window("LifeGPT", id: "main") {
            RootView().environment(model)
                .preferredColorScheme(model.settings.appearance == "dark" ? .dark : model.settings.appearance == "light" ? .light : nil)
                .tint(.lifeAccent)
        }
        .defaultSize(width: 1160, height: 790)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Life…") { model.showNewLife = true }.keyboardShortcut("n").disabled(model.busy)
                Button("Import Life…") { model.importLife() }.keyboardShortcut("o").disabled(model.busy)
            }
            CommandGroup(after: .saveItem) {
                Button("Export Save…") { model.exportBackup() }.disabled(model.snapshot == nil || model.busy)
                Button("Export Story…") { model.exportStory() }.disabled(model.snapshot == nil)
            }
            CommandMenu("Life") {
                Button("Story Settings…") { model.showStorySettings = true }.disabled(model.snapshot == nil || model.busy)
                Button("World & Economy…") { model.showWorldEditor = true }.disabled(model.snapshot == nil || model.busy)
                Divider()
                Button("Show Inspector") { model.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
                Button("Show Saves in Finder") { model.revealSaves() }
            }
        }
        Settings { SettingsView().environment(model).tint(.lifeAccent) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
