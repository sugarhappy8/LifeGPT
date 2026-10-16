import SwiftUI
import LifeCore

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    let snapshot: LifeSnapshot
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                Picker("Inspect", selection: $model.inspectorTab) {
                    ForEach(InspectorTab.allCases) { tab in Label(tab.rawValue, systemImage: tab.symbol).tag(tab) }
                }.labelsHidden().pickerStyle(.menu)
                Spacer()
                Text("LIFE RECORD").font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(.tertiary)
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch model.inspectorTab {
                    case .life: life
                    case .finances: finances
                    case .people: people
                    case .decisions: decisions
                    case .timeline: timeline
                    case .paths: paths
                    case .memory: memory
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private var life: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "The person")
            Text(snapshot.character.name).font(.system(size: 27, design: .serif))
            fact("Born", "\(snapshot.character.birthYear.description), \(snapshot.character.birthplace)")
            fact("Appearance", snapshot.character.appearance)
            fact("Family", snapshot.character.familyWealthTier.rawValue.replacingOccurrences(of: "ultraWealthy", with: "Ultra-wealthy"))
            if let background = snapshot.character.background, !background.isEmpty { fact("Background", background) }
            Divider()
            SectionLabel(text: "Life now")
            if snapshot.state.isEmpty { Text("Your choices will begin to shape this life.").font(.callout).foregroundStyle(.secondary) }
            ForEach(snapshot.state.keys.filter { !$0.hasPrefix("_engine_") }.sorted(), id: \.self) { key in fact(key.replacingOccurrences(of: "_", with: " ").capitalized, snapshot.state[key] ?? "") }
            if let brief = snapshot.world.last {
                if snapshot.worldNeedsReview {
                    Label("The setting has moved on. Review its context and prices.", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.orange)
                }
                Divider(); SectionLabel(text: "Place & time")
                Text(brief.location).font(.headline)
                Text(brief.text).font(.callout).lineSpacing(4).textSelection(.enabled)
                Button("Review world & economy…") { model.showWorldEditor = true }.buttonStyle(.link).disabled(model.busy)
            }
        }
    }
    private var finances: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel(text: "Your finances")
            Text(money(snapshot.balance)).font(.system(size: 24, weight: .medium, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text("Accessible cash across your accounts").font(.caption).foregroundStyle(.secondary)
            fact("Legacy net income / month", money(snapshot.monthlyIncome))
            fact("Company cash", money(snapshot.businessCash))
            fact("Reserved taxes", money(snapshot.reservedTaxes))
            fact("Gross business revenue / month", money(snapshot.monthlyTotal(.revenue)))
            fact("Gross owner pay / month", money(snapshot.monthlyTotal(.ownerSalary)))
            fact("Employee payroll / month", money(snapshot.monthlyTotal(.payroll)))
            fact("Operating costs / month", money(snapshot.monthlyTotal(.expense)))
            fact("Unpaid obligations", money(snapshot.unpaidObligations))
            if snapshot.internalReceivables > 0 { fact("Internal net receivables", money(snapshot.internalReceivables)) }
            Button("Businesses & payroll…") { model.showBusinessManager = true }.buttonStyle(.bordered).disabled(model.busy)
            Button("Manage finances…") { model.showFinanceManager = true }.buttonStyle(.bordered).disabled(model.busy)
            ForEach(snapshot.accounts) { account in
                fact(account.name, "\(money(account.balanceMinor)) · \(account.kind.rawValue) · \(account.status.rawValue) · \(account.access.rawValue)")
            }
            HStack { metric("Assets", snapshot.assets); Spacer(); metric("Debt", snapshot.debt) }
            fact("Net worth", money(snapshot.netWorth))
            fact("Your monthly living costs", money(snapshot.personalLivingCost))
            Text(snapshot.household.label).font(.caption).foregroundStyle(.secondary)
            Button("Change household & difficulty…") { model.showStorySettings = true }.buttonStyle(.link).disabled(model.busy)
            Divider(); SectionLabel(text: "Income")
            let active = snapshot.streams.filter { stream in stream.endedOn == nil && snapshot.accessibleAccounts.contains { $0.id == stream.accountId } }
            if active.isEmpty && snapshot.currentObligations.isEmpty { Text("No income is recorded yet. Describe your earnings in the story or add a source in Manage finances.").font(.callout).foregroundStyle(.secondary) }
            ForEach(active, id: \.name) { stream in
                fact(stream.name, "\(money(stream.monthlyMinor)) / month → \(snapshot.accounts.first { $0.id == stream.accountId }?.name ?? stream.accountId)")
            }
            Text("Income pays on the first of each month crossed. Transfers move existing funds; they do not create earnings.").font(.caption).foregroundStyle(.secondary)
            if !snapshot.ownedPositions.filter({ $0.principalMinor > 0 }).isEmpty {
                Divider(); SectionLabel(text: "Assets & debts")
                ForEach(snapshot.ownedPositions.filter { $0.principalMinor > 0 }) { position in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(position.name).font(.callout.weight(.medium))
                        Text("\(position.kind.rawValue.capitalized) · \(money(position.principalMinor))").font(.caption).foregroundStyle(.secondary)
                        if position.annualRateBPS > 0 { Text("\(Double(position.annualRateBPS) / 100, specifier: "%.1f")% annually").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            Divider(); SectionLabel(text: "Recent ledger")
            ForEach(snapshot.ledger, id: \.id) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.sourceType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption.weight(.medium))
                        Spacer(minLength: 3)
                        Text((entry.amountMinor > 0 ? "+" : "") + money(entry.amountMinor)).font(.system(size: 11, design: .monospaced)).foregroundStyle(entry.amountMinor > 0 ? Color.lifeAccent : Color.primary)
                    }
                    Text(entry.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(snapshot.accounts.first { $0.id == entry.accountId }?.name ?? entry.accountId).font(.caption2).foregroundStyle(.secondary)
                    Text(entry.date.iso).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }.padding(.vertical, 3)
            }
            if snapshot.ledger.count == 500 { Text("Showing the latest 500 entries. Export the save to keep the complete ledger.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var people: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "The people in your life")
            if snapshot.cast.isEmpty { EmptyNote(title: "A cast yet to meet", detail: "People you encounter become part of this life's memory.") }
            ForEach(snapshot.cast, id: \.name) { person in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(person.name).font(.system(size: 20, design: .serif))
                        Spacer()
                        if person.status != "alive" { Text(person.status.capitalized).font(.caption2).foregroundStyle(.secondary) }
                    }
                    if let relation = person.relation { Text(relation.capitalized).font(.caption.weight(.medium)).foregroundStyle(Color.lifeAccent) }
                    if let notes = person.notes { Text(notes).font(.callout).lineSpacing(3).textSelection(.enabled) }
                    Text("Met \(person.firstMet.iso) · Last seen \(person.lastSeen.iso)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
                Divider()
            }
        }
    }
    private var decisions: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "The choices that shape you")
            if snapshot.decisions.isEmpty { EmptyNote(title: "An unwritten chapter", detail: "Major choices and their consequences will be remembered here.") }
            ForEach(Array(snapshot.decisions.enumerated()), id: \.offset) { _, decision in
                VStack(alignment: .leading, spacing: 7) {
                    Text(decision.date.iso).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Text(decision.summary).font(.headline)
                    Text(decision.choice).font(.callout).foregroundStyle(.secondary)
                    if decision.importance == .major { Text("A turning point").font(.caption2).foregroundStyle(Color.lifeAccent) }
                }
                Divider()
            }
        }
    }
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "Moments, remembered")
            if snapshot.events.isEmpty { EmptyNote(title: "The beginning", detail: "Notable events will form a timeline as this life unfolds.") }
            ForEach(snapshot.events) { event in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(event.importance == .major ? Color.lifeAccent : Color.secondary.opacity(0.4)).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.date.iso).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Text(event.title).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if event.uncanny { Text("Something uncanny").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
    private var paths: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionLabel(text: "Ideas into possibilities")
            if snapshot.paths.isEmpty { EmptyNote(title: "Start with an idea", detail: "Tell the narrator what you want to build. A business grows through capital, launch, traction, and profit.") }
            ForEach(snapshot.paths) { path in
                VStack(alignment: .leading, spacing: 9) {
                    Text(path.title).font(.system(size: 21, design: .serif))
                    Text(path.stage.rawValue.capitalized).font(.caption.weight(.semibold)).foregroundStyle(Color.lifeAccent)
                    ProgressView(value: Double(min(path.stage.ordinal, 4)), total: 4).tint(.lifeAccent)
                    Text(path.notes).font(.callout).foregroundStyle(.secondary)
                    Text("Capital invested: \(money(path.investedMinor))").font(.caption)
                    Text("Current stage since \(path.stageStartedOn.iso)").font(.caption2).foregroundStyle(.tertiary)
                }
                Divider()
            }
            SectionLabel(text: "Unfinished stories")
            ForEach(snapshot.threads.filter { !$0.resolved }) { thread in fact(thread.title, thread.notes) }
            if snapshot.threads.allSatisfy(\.resolved) { Text("No open threads yet.").font(.callout).foregroundStyle(.secondary) }
        }
    }
    private var memory: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "A life kept locally")
            Text("\(snapshot.totalMessages) messages · \(snapshot.logs.count) turns · \(snapshot.chapters.count) chapters").font(.callout)
            Text("Older scenes are condensed into excerpts for the narrator. The complete transcript stays in your save.").font(.caption).foregroundStyle(.secondary)
            ForEach(snapshot.chapters.reversed()) { chapter in
                DisclosureGroup("Chapter through \(chapter.date.iso)") { Text(chapter.text).font(.caption).textSelection(.enabled).padding(.top, 8) }
            }
            Divider(); SectionLabel(text: "Latest turn audit")
            if let log = snapshot.logs.last {
                fact("Fate roll", "\(log.fate) / 100")
                if let difficulty = snapshot.state["_engine_last_difficulty"],
                   let effective = snapshot.state["_engine_last_effective_fate"] {
                    fact("After difficulty adjustment", "\(effective) / 100 · difficulty \(difficulty)")
                }
                fact("Model usage", "\(log.inputTokens.grouped) input · \(log.outputTokens.grouped) output tokens")
                fact("Repair", log.repaired ? "A correction was requested" : "Not needed")
                if !log.rejections.isEmpty { DisclosureGroup("Validation notes (\(log.rejections.count))") {
                    Text(log.rejections.joined(separator: "\n\n")).font(.caption).textSelection(.enabled).padding(.top, 8)
                } }
            } else { Text("No turns yet.").font(.callout).foregroundStyle(.secondary) }
            Button("Export this life…") { model.exportBackup() }.buttonStyle(.bordered).disabled(model.busy)
        }
    }
    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
    private func metric(_ label: String, _ amount: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption).foregroundStyle(.secondary); Text(money(amount)).font(.system(size: 12, design: .monospaced)) }
    }
    private func money(_ value: Int64) -> String { Money.format(value, economy: snapshot.economy) }
}
