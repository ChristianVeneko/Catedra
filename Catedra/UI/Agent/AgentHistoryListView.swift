import SwiftUI

/// Content column for a course's agent: past conversations, newest first.
struct AgentHistoryListView: View {
    @Environment(AppContainer.self) private var container
    let scope: AgentScope
    let color: Color

    var body: some View {
        let registry = container.agents
        let runs = registry.runs(in: scope.id)
        List {
            Button {
                registry.selection[scope.id] = nil
            } label: {
                Label("Nueva conversación", systemImage: "plus.bubble").foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .disabled(registry.isRunning(scopeID: scope.id))
            Section("Historial") {
                if runs.isEmpty { Text("Aún no hay conversaciones.").foregroundStyle(.secondary) }
                ForEach(runs) { run in
                    Button { registry.selection[scope.id] = run.id } label: {
                        HStack(spacing: 10) {
                            AgentProviderMark(provider: run.provider, size: 16)
                            Image(systemName: run.status.symbol).foregroundStyle(run.status.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title).lineLimit(2).font(.headline)
                                Text("\(run.status.label) · \(Formatters.relative(run.startedAt))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if run.isRunning { AgentActivityDot(providers: [run.provider]) }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(registry.selection[scope.id] == run.id ? color.opacity(0.15) : Color.clear)
                    .contextMenu {
                        Button("Eliminar", role: .destructive) { registry.delete(runID: run.id) }.disabled(run.isRunning)
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Agente · \(scope.title)")
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
    }
}
