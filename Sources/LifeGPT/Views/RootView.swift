import SwiftUI
import LifeCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 290)
        } detail: {
            Group {
                if let snapshot = model.snapshot { ChatView(snapshot: snapshot) }
                else { WelcomeView() }
            }
            .background(Color.lifePaper)
            .inspector(isPresented: $model.showInspector) {
                if let snapshot = model.snapshot { InspectorView(snapshot: snapshot).inspectorColumnWidth(min: 260, ideal: 300, max: 420) }
                else { EmptyNote(title: "A life, in detail", detail: "Your character, finances, and memories will appear here.").padding(24) }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.snapshot != nil {
                        Button { model.showStorySettings = true } label: { Label("Story settings", systemImage: "slider.horizontal.3") }
                            .help("Play style, difficulty, household and storytelling").disabled(model.busy)
                        Menu {
                            Button("World & Economy…") { model.showWorldEditor = true }
                            Button("Manage finances…") { model.showFinanceManager = true }
                            Button("Businesses & payroll…") { model.showBusinessManager = true }
                            Button("How to prompt for roleplay…") { model.showRoleplayGuide = true }
                            Button("Export Save…") { model.exportBackup() }
                            Button("Export Story…") { model.exportStory() }
                            Divider()
                            Button("Delete Life…", role: .destructive) { model.deleteCandidate = model.selection }
                        } label: { Image(systemName: "ellipsis.circle") }.disabled(model.busy).help("Life actions")
                    }
                    Button { model.showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }.help("Toggle life inspector")
                    Button { model.showRoleplayGuide = true } label: { Label("How to prompt for roleplay", systemImage: "questionmark.circle") }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .sheet(isPresented: $model.showNewLife) { NewLifeView().environment(model) }
        .sheet(isPresented: $model.showStorySettings) {
            if let snapshot = model.snapshot { StorySettingsView(snapshot: snapshot).environment(model) }
        }
        .sheet(isPresented: $model.showWorldEditor) {
            if let snapshot = model.snapshot { WorldEditorView(snapshot: snapshot).environment(model) }
        }
        .sheet(isPresented: $model.showFinanceManager) {
            if let snapshot = model.snapshot { FinanceManagerView(snapshot: snapshot).environment(model) }
        }
        .sheet(isPresented: $model.showBusinessManager) {
            if let snapshot = model.snapshot { BusinessManagerView(snapshot: snapshot).environment(model) }
        }
        .sheet(isPresented: $model.showRoleplayGuide) { RoleplayGuideView() }
        .alert("Delete this life permanently?", isPresented: Binding(get: { model.deleteCandidate != nil }, set: { if !$0 { model.deleteCandidate = nil } })) {
            Button("Cancel", role: .cancel) { model.deleteCandidate = nil }
            Button("Delete Life", role: .destructive) { if let id = model.deleteCandidate { model.deleteLife(id) } }
        } message: { Text("The character, story, and all memories in this save will be removed. Export a save first if you want to keep a copy.") }
        .task { await model.refreshUsage() }
    }
}

private struct SidebarView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LifeMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LifeGPT").font(.system(size: 17, weight: .semibold, design: .serif))
                    Text("ONE LIFE AT A TIME").font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            Button { model.showNewLife = true } label: {
                Label("Begin a new life", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.borderedProminent).disabled(model.busy).padding(.horizontal, 14)
            TextField("Find a life", text: $model.search).textFieldStyle(.roundedBorder).padding(14)
            HStack { SectionLabel(text: "Your lives"); Spacer(); Text(model.lives.count.description).font(.caption).foregroundStyle(.tertiary) }.padding(.horizontal, 18)
            List {
                ForEach(model.filteredLives, id: \.id) { life in
                    Button { model.openLife(life.id) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(model.selection == life.id ? Color.lifeAccent : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(life.characterName).font(.system(size: 14, weight: model.selection == life.id ? .semibold : .regular)).foregroundStyle(.primary)
                                Text("Age \(life.ageYears) · \(life.currentDate.year.description)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 7).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(model.busy)
                    .listRowBackground(model.selection == life.id ? Color.lifeAccent.opacity(0.10) : Color.clear)
                    .contextMenu {
                        Button("Open") { model.openLife(life.id) }
                        Button("Delete…", role: .destructive) { model.deleteCandidate = life.id }
                    }
                }
            }.listStyle(.sidebar)
            if !model.libraryWarnings.isEmpty {
                Button { model.information = model.libraryWarnings.joined(separator: "\n") } label: {
                    Label("\(model.libraryWarnings.count) unreadable save(s)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }.buttonStyle(.plain).padding(12)
            }
            Divider()
            HStack {
                SettingsLink { Label("Settings", systemImage: "gearshape").font(.callout) }.buttonStyle(.plain)
                Spacer()
                Button { model.importLife() } label: { Image(systemName: "square.and.arrow.down") }.buttonStyle(.plain).help("Import a life").disabled(model.busy)
            }.padding(16)
            HStack(spacing: 5) {
                Circle().fill(Color.lifeAccent).frame(width: 5, height: 5)
                Text(model.providerLabel).lineLimit(1)
                Spacer()
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 14)
        }
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            LifeMark(size: 64)
            SectionLabel(text: "A story only you can live")
            Text("Every life starts\nwith a possibility.").font(.system(size: 43, weight: .regular, design: .serif)).tracking(-1)
            Text("Choose a person, a place, and a moment in time. Then find out who you become, one conversation at a time.")
                .font(.system(size: 17)).foregroundStyle(.secondary).lineSpacing(5).frame(maxWidth: 440, alignment: .leading)
            HStack(spacing: 14) {
                Button("Begin a life") { model.showNewLife = true }.buttonStyle(.borderedProminent).controlSize(.large)
                SettingsLink { Text("Choose a narrator") }.buttonStyle(.bordered).controlSize(.large)
            }
            if let error = model.error { NoticeBar(text: error, isError: true) { model.error = nil } }
            Spacer()
            Text("Saved on your Mac. Your AI provider is your choice.").font(.caption).foregroundStyle(.secondary)
        }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
