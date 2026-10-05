import SwiftUI
import AppKit

/// Renders the menu bar label as an image so the urgency color survives (labels are otherwise tinted as templates).
@MainActor
enum MenuBarImage {
    static func make(_ label: MenuBarLabel, syncing: Bool, focus: (text: String, isRest: Bool)? = nil) -> NSImage {
        let color: Color = switch label.tone {
        case .normal: .black
        case .warning: .orange
        case .critical: .red
        }
        let content = HStack(spacing: 4) {
            Image(systemName: focus != nil ? (focus?.isRest == true ? "cup.and.saucer.fill" : "timer")
                  : syncing ? "arrow.triangle.2.circlepath" : "graduationcap.fill")
            if let focus { Text(focus.text).monospacedDigit() } else if let text = label.text { Text(text).monospacedDigit() }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 1)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = label.tone == .normal
        return image
    }
}

struct MenuBarLabelView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let now = container.clock.now
        let ws = container.workspace
        let next = UpcomingActivities.next(ws.snapshot.activities, stateOf: { ws.state(of: $0, now: now) }, now: now, limit: 1).first
        let label = MenuBarLabel.make(nextDue: next?.due, now: now, showsCountdown: container.settings.menuBarShowsCountdown)
        let focus = container.focus
        let focusLabel = focus.remainingText.map { (text: $0, isRest: focus.phase == .rest) }
        Image(nsImage: MenuBarImage.make(label, syncing: container.sync.isRunning, focus: focusLabel))
            .accessibilityLabel(focusLabel.map { "Cátedra, enfoque: quedan \($0.text)" }
                                ?? label.text.map { "Cátedra, próxima entrega en \($0)" } ?? "Cátedra")
            .onAppear { registerOpener() }
    }

    private func registerOpener() {
        let open = openWindow
        container.openWindowByID = { open(id: $0) }
    }
}

/// Popover of the menu bar extra.
struct MenuBarPopover: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .frame(width: 340)
        .onAppear {
            let open = openWindow
            container.openWindowByID = { open(id: $0) }
            container.review.reload(courses: container.workspace.snapshot.courses, root: container.workspace.root)
        }
    }

    private func content(now: Date) -> some View {
        let ws = container.workspace
        let upcoming = UpcomingActivities.next(ws.snapshot.activities, stateOf: { ws.state(of: $0, now: now) }, now: now, limit: 6)
        return VStack(alignment: .leading, spacing: 12) {
            if let hero = upcoming.first {
                NextActivityCard(activity: hero, now: now)
                if upcoming.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Próximas").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(upcoming.dropFirst()) { activity in
                            UpcomingRow(activity: activity, now: now)
                        }
                    }
                }
            } else {
                Label("No hay entregas pendientes con fecha.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary).padding(.vertical, 8)
            }
            reviewRow(now: now)
            focusRow(upcoming: upcoming)
            runningAgents
            Divider()
            footer
        }
        .padding(14)
        .animation(.snappy, value: upcoming.map(\.id))
    }

    @ViewBuilder
    private func reviewRow(now: Date) -> some View {
        if container.review.hasAnyCards {
            let count = container.review.todayCount(today: ReviewDay(date: now))
            Button {
                container.navigation.sidebar = .review
                container.showMainWindow()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle").foregroundStyle(.secondary).frame(width: 16)
                    Text("Tarjetas para hoy")
                    Spacer()
                    Text("\(count)").font(.callout.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(count == 0 ? Color.secondary : Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(ReviewSummary.todayText(count))
        }
    }

    @ViewBuilder
    private func focusRow(upcoming: [Activity]) -> some View {
        let focus = container.focus
        if focus.isRunning {
            HStack(spacing: 8) {
                Image(systemName: focus.phase == .rest ? "cup.and.saucer" : "timer").foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(focus.phase == .rest ? "Descanso" : "Enfoque").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let name = focus.activityName { Text(name).lineLimit(1) }
                }
                Spacer()
                Text(focus.remainingText ?? "").monospacedDigit().font(.callout.weight(.semibold))
                Button("Detener") { focus.stop() }.controlSize(.small)
            }
        } else if !upcoming.isEmpty {
            Menu {
                ForEach(upcoming) { activity in
                    Button(activity.name) { focus.start(activityID: activity.id, name: activity.name) }
                }
            } label: {
                Label("Iniciar enfoque en…", systemImage: "timer")
            }
            .controlSize(.small).fixedSize()
        }
    }

    @ViewBuilder
    private var runningAgents: some View {
        let running = container.agents.runningRuns
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agentes en ejecución").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(running) { run in
                    HStack(spacing: 8) {
                        AgentProviderMark(provider: run.provider, size: 16, animation: .spin)
                        Text(run.scope.title).lineLimit(1)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(AgentFormat.elapsed(ctx.date.timeIntervalSince(run.turnStartedAt)))
                                .monospacedDigit().foregroundStyle(.secondary).font(.caption)
                        }
                        Button("Ver") {
                            container.navigation.open(run: run, registry: container.agents)
                            container.showMainWindow()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var footer: some View {
        let sync = container.sync
        return VStack(alignment: .leading, spacing: 8) {
            if sync.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(sync.currentCourse.map { "Sincronizando · \($0)" } ?? "Sincronizando…").font(.callout).lineLimit(1)
                    Spacer()
                    Button("Ver registro") { sync.isPresented = true; container.showMainWindow() }.controlSize(.small)
                }
            }
            HStack {
                Menu {
                    Button("Sincronizar sin archivos") { sync.start(includeFiles: false) }
                } label: {
                    Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
                } primaryAction: {
                    if NSEvent.modifierFlags.contains(.option) { sync.start(includeFiles: false) } else { sync.start(includeFiles: true) }
                }
                .disabled(sync.isRunning)
                .fixedSize()
                Spacer()
                Button("Abrir Cátedra") { container.showMainWindow() }
                Button { container.openSettingsWindow() } label: { Label("Ajustes", systemImage: "gearshape") }
                    .labelStyle(.iconOnly).help("Ajustes")
                Button("Salir") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

private struct NextActivityCard: View {
    @Environment(AppContainer.self) private var container
    let activity: Activity
    let now: Date

    var body: some View {
        let course = container.workspace.course(for: activity)
        let color = CoursePalette.color(for: course)
        let label = MenuBarLabel.make(nextDue: activity.due, now: now, showsCountdown: true)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Label(activity.kind.displayName, systemImage: activity.kind.symbolName)
                    .font(.caption).foregroundStyle(color)
                Text(activity.name).font(.headline).lineLimit(2)
                Text(activity.courseName).font(.caption).foregroundStyle(.secondary)
                Text(label.text ?? "").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(tint(label.tone))
                HStack {
                    Button("Abrir") { container.reveal(activity: activity) }
                    if let url = activity.url { Button("SAIA") { NSWorkspace.shared.open(url) } }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(10).card(tint: color)
    }

    private func tint(_ tone: MenuBarLabel.Tone) -> Color {
        switch tone { case .normal: .primary; case .warning: .orange; case .critical: .red }
    }
}

private struct UpcomingRow: View {
    @Environment(AppContainer.self) private var container
    let activity: Activity
    let now: Date

    var body: some View {
        let color = CoursePalette.color(for: container.workspace.course(for: activity))
        Button { container.reveal(activity: activity) } label: {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Image(systemName: activity.kind.symbolName).foregroundStyle(.secondary).frame(width: 16)
                Text(activity.name).lineLimit(1)
                Spacer()
                Text(activity.due.map { CountdownFormatter.text(until: $0, from: now) } ?? "")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
