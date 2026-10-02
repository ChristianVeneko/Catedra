import SwiftUI

/// Toolbar badge: number of running agents with a popover to jump to them.
struct RunningAgentsBadge: View {
    @Environment(AppContainer.self) private var container
    @State private var shown = false

    var body: some View {
        let running = container.agents.runningRuns
        if !running.isEmpty {
            Button { shown.toggle() } label: {
                Label { Text("\(running.count)").monospacedDigit() } icon: { ClaudeMarkView(size: 16, animation: .spin) }
            }
            .help("Agentes en ejecución")
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agentes en ejecución").font(.headline).padding(.bottom, 4)
                    ForEach(running) { run in
                        Button {
                            container.navigation.open(run: run, registry: container.agents)
                            shown = false
                        } label: {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                VStack(alignment: .leading) {
                                    Text(run.scope.title).lineLimit(1)
                                    Text(run.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14).frame(width: 300)
            }
        }
    }
}
