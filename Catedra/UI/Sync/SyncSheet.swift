import SwiftUI

struct SyncSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let sync = container.sync
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if sync.isRunning { ProgressView().controlSize(.small) }
                else { Image(systemName: icon).foregroundStyle(tint).font(.title2) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.semibold))
                    if let course = sync.currentCourse, sync.isRunning {
                        Text(course).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if case .finished(let outcome) = sync.state { OutcomeView(outcome: outcome) }

            GroupBox("Registro") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(sync.log) { line in
                                Text(line.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(line.isError ? Color.red : (isCourse(line) ? Color.primary : Color.secondary))
                                    .fontWeight(isCourse(line) ? .semibold : .regular)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: sync.log.count) { _, _ in
                        if let last = sync.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .frame(minHeight: 160)
            }

            HStack {
                if case .finished(let outcome) = sync.state, needsSettings(outcome) {
                    Button("Abrir Ajustes") { dismiss(); openSettings() }
                }
                Spacer()
                if sync.isRunning { Button("Cancelar", role: .cancel) { sync.cancel() } }
                else {
                    Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }

    private func isCourse(_ line: SyncLogLine) -> Bool {
        if case .course = line.event { true } else { false }
    }

    private func needsSettings(_ outcome: SyncOutcome) -> Bool {
        switch outcome {
        case .loginFailed, .missingCredentials, .missingPython: true
        default: false
        }
    }

    private var title: String {
        switch container.sync.state {
        case .idle: "Sincronización"
        case .running: container.sync.lastIncludeFiles ? "Sincronizando con SAIA…" : "Sincronizando metadatos…"
        case .finished(.success): "Sincronización completada"
        case .finished: "La sincronización no se completó"
        }
    }

    private var icon: String {
        if case .finished(.success) = container.sync.state { return "checkmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var tint: Color {
        if case .finished(.success) = container.sync.state { return .green }
        return .orange
    }
}

private struct OutcomeView: View {
    let outcome: SyncOutcome

    var body: some View {
        switch outcome {
        case .success(let diff): DiffSummaryView(diff: diff)
        case .loginFailed(let detail):
            message("No se pudo iniciar sesión en SAIA. Revise su usuario y contraseña en Ajustes. \(detail)")
        case .missingCredentials:
            message("Aún no hay credenciales guardadas. Ingréselas en Ajustes para sincronizar.")
        case .missingPython:
            message("No se encontró un intérprete de Python válido. Configure uno en Ajustes.")
        case .installFailed(let detail):
            message("No se pudo preparar el script de sincronización. \(detail)")
        case .failed(let code):
            message(code == -15 ? "La sincronización fue cancelada." : "El proceso terminó con errores (código \(code)). Revise el registro.")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DiffSummaryView: View {
    let diff: ActivityDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if diff.isEmpty {
                Label("Sin cambios en las actividades.", systemImage: "equal.circle").foregroundStyle(.secondary)
            } else {
                if !diff.added.isEmpty { row("Nuevas", diff.added.map(\.name), "plus.circle.fill", .green) }
                if !diff.removed.isEmpty { row("Eliminadas", diff.removed.map(\.name), "minus.circle.fill", .red) }
                if !diff.dueChanges.isEmpty {
                    row("Fechas modificadas", diff.dueChanges.map { "\($0.activity.name): \(text($0.oldValue)) → \(text($0.newValue))" },
                        "calendar.badge.clock", .orange)
                }
                if !diff.statusChanges.isEmpty {
                    row("Estados modificados", diff.statusChanges.map { "\($0.activity.name): \($0.oldValue) → \($0.newValue)" },
                        "arrow.triangle.2.circlepath", .blue)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func text(_ date: Date?) -> String { date.map(Formatters.due) ?? "sin fecha" }

    private func row(_ title: String, _ items: [String], _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(title) (\(items.count))", systemImage: symbol).foregroundStyle(color).font(.callout.weight(.semibold))
            ForEach(items.prefix(6), id: \.self) { Text("• \($0)").font(.caption).lineLimit(2) }
            if items.count > 6 { Text("… y \(items.count - 6) más").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
