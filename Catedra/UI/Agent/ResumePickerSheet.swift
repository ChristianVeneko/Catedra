import SwiftUI

/// Sheet for `/resume`: past conversations of this folder (or all folders) from the run store.
struct ResumePickerSheet: View {
    let scope: AgentScope
    let runs: [AgentRun]
    let pick: (AgentRun) -> Void
    let cancel: () -> Void

    @State private var allScopes = false

    private var visible: [AgentRun] {
        runs.filter { allScopes || $0.scope.id == scope.id }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Retomar una conversación").font(.title3.weight(.semibold))
            Toggle("Mostrar todas las carpetas", isOn: $allScopes).toggleStyle(.switch)
            if visible.isEmpty {
                ContentUnavailableView("Sin conversaciones", systemImage: "clock.arrow.circlepath",
                                       description: Text("Aún no hay conversaciones guardadas para mostrar."))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(visible) { run in
                    Button { pick(run) } label: {
                        HStack(spacing: 10) {
                            AgentProviderMark(provider: run.provider, size: 16)
                            Image(systemName: run.status.symbol).foregroundStyle(run.status.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title).lineLimit(1)
                                Text(allScopes ? "\(run.scope.title) · \(Formatters.relative(run.startedAt))" : Formatters.relative(run.startedAt))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if run.sessionId == nil { Text("Sin sesión").font(.caption).foregroundStyle(.secondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(run.isRunning)
                }
                .frame(minHeight: 240)
            }
            HStack {
                Text("Elegir una conversación de otra carpeta abre esa carpeta.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar", action: cancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 520)
    }
}

/// Sheet for `/archivos`: files the agent generated in this scope.
struct GeneratedFilesSheet: View {
    let files: [URL]
    let preview: (URL) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Archivos generados").font(.title3.weight(.semibold))
            if files.isEmpty {
                ContentUnavailableView("Sin archivos", systemImage: "doc",
                                       description: Text("El agente aún no ha generado archivos en esta carpeta."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(files, id: \.self) { url in
                            FileRow(url: url, preview: { preview(url) })
                            if url != files.last { Divider().padding(.leading, 46) }
                        }
                    }
                }
                .frame(maxHeight: 320).card()
            }
            HStack { Spacer(); Button("Cerrar", action: close).keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 520)
    }
}
