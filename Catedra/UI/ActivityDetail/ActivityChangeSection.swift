import SwiftUI

/// Diff of an edited statement and the date changes, with "Marcar como visto".
struct ActivityChangeSection: View {
    @Environment(AppContainer.self) private var container
    let change: ActivityChange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cambios detectados")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(ActivityChangeNotification.badges(for: change), id: \.self) { ChangeBadge(text: $0) }
                    Spacer()
                    Text("Detectado \(Formatters.relative(change.detectedAt))").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(change.dateChanges, id: \.field) { dateChange in
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                        Text("\(dateChange.field.label):").fontWeight(.medium)
                        Text(text(dateChange.old)).strikethrough().foregroundStyle(.red)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(text(dateChange.new)).foregroundStyle(.green)
                    }
                    .font(.callout)
                }
                if change.textChanged { diffView }
                HStack {
                    Spacer()
                    Button("Marcar como visto") { container.changes.markSeen(change.activityID) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func text(_ date: Date?) -> String { date.map(Formatters.due) ?? "sin fecha" }

    private var diffView: some View {
        let lines = change.diff
        return VStack(alignment: .leading, spacing: 4) {
            Text("Enunciado: \(lines.addedCount) líneas añadidas, \(lines.removedCount) eliminadas")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(LineDiff.condensed(lines).enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .gap(let count):
                        Text("⋯ \(count) \(count == 1 ? "línea sin cambios" : "líneas sin cambios")")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 3)
                    case .line(let line):
                        DiffLineView(line: line)
                    }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker).font(.system(.callout, design: .monospaced).weight(.bold)).foregroundStyle(tint).frame(width: 12)
            Text(line.text.isEmpty ? " " : line.text).font(.system(.callout, design: .monospaced))
                .foregroundStyle(line.kind == .unchanged ? Color.secondary : tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(tint.opacity(line.kind == .unchanged ? 0 : 0.12))
        .accessibilityLabel((line.kind == .added ? "Añadida: " : line.kind == .removed ? "Eliminada: " : "") + line.text)
    }

    private var marker: String { line.kind == .added ? "+" : line.kind == .removed ? "−" : "" }
    private var tint: Color { line.kind == .added ? .green : line.kind == .removed ? .red : .secondary }
}

struct ChangeBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "pencil.line").font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(.purple).background(Color.purple.opacity(0.14), in: Capsule())
    }
}

/// "Plan listo" / "Cambió ..." badges shown on activity cards and headers.
struct ActivityFlagBadges: View {
    @Environment(AppContainer.self) private var container
    let activityID: String

    var body: some View {
        HStack(spacing: 4) {
            if let change = container.changes.change(for: activityID) {
                ForEach(ActivityChangeNotification.badges(for: change), id: \.self) { ChangeBadge(text: $0) }
            }
            if container.autopilot.planStatus(for: activityID) == .ready {
                Label("Plan listo", systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .foregroundStyle(.teal).background(Color.teal.opacity(0.14), in: Capsule())
            }
        }
    }
}

/// Start/stop of the focus timer and the time invested in one activity.
struct FocusSection: View {
    @Environment(AppContainer.self) private var container
    let activity: Activity

    var body: some View {
        let focus = container.focus
        let total = focus.totalMinutes(for: activity.id)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Enfoque")
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if focus.isRunning(activityID: activity.id), let remaining = focus.remainingText {
                        Text(remaining).font(.title2.weight(.bold)).monospacedDigit()
                        Text(focus.phase == .rest ? "Descanso" : "Sesión de enfoque en curso").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Tiempo invertido: \(FocusAggregation.text(minutes: total))").font(.headline)
                        Text("Sesiones de \(container.settings.focusSettings.focusMinutes) min con descansos de \(container.settings.focusSettings.breakMinutes) min.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if focus.isRunning(activityID: activity.id) {
                    Button("Detener") { focus.stop() }
                } else {
                    Button(focus.isRunning ? "Cambiar a esta actividad" : "Iniciar enfoque") {
                        focus.start(activityID: activity.id, name: activity.name)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            if focus.isRunning(activityID: activity.id), total > 0 {
                Text("Acumulado en esta actividad: \(FocusAggregation.text(minutes: total))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
