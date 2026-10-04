import SwiftUI

/// Toolbar indicator with the total memory of running agents; opens the resource manager popover.
struct ResourceIndicator: View {
    @Environment(AppContainer.self) private var container
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Label { Text(ResourceFormatter.bytes(container.resources.indicatorRSS)).monospacedDigit() } icon: {
                Image(systemName: "memorychip")
            }
        }
        .help("Administrador de recursos")
        .popover(isPresented: $shown, arrowEdge: .bottom) { ResourceManagerView() }
        .onChange(of: shown) { _, now in container.resources.isVisible = now }
        .task { container.resources.start() }
    }
}

struct ResourceManagerView: View {
    @Environment(AppContainer.self) private var container
    @State private var collapsed: Set<String> = []
    @State private var confirmingClean = false

    private var model: ResourceMonitorModel { container.resources }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            totals
            columnHeader
            Divider()
            tree
            Divider()
            DiskSection()
        }
        .frame(width: 440)
        .alert("¿Detener todos los agentes?", isPresented: $confirmingClean) {
            Button("Detener todos", role: .destructive) {
                for run in container.agents.runningRuns { container.agents.stop(runID: run.id) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se cancelarán los \(container.agents.runningCount) agentes en ejecución. La sincronización no se detiene.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Administrador de recursos").font(.headline)
            Spacer()
            Button { Task { await model.sample() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Actualizar")
            Button { confirmingClean = true } label: { Image(systemName: "trash") }
                .help("Detener todos los agentes")
                .disabled(container.agents.runningCount == 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var totals: some View {
        Text("\(ResourceFormatter.cpu(model.report.totalCPU)) · \(ResourceFormatter.bytes(model.report.totalRSS)) Σ RSS")
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Nombre").frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU").frame(width: 64, alignment: .trailing)
            Text("RSS").frame(width: 76, alignment: .trailing)
            Color.clear.frame(width: 22)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 4)
    }

    @ViewBuilder
    private var tree: some View {
        if model.report.roots.isEmpty {
            ContentUnavailableView("Sin procesos en ejecución", systemImage: "memorychip",
                                   description: Text("Los agentes y la sincronización aparecerán aquí mientras trabajan."))
                .frame(height: 150)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.report.roots) { node in
                        ResourceRow(node: node, depth: 0, collapsed: $collapsed, onKill: kill)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
        }
    }

    private func kill(_ key: TrackedProcessKey) {
        switch key {
        case .agent(let id): container.agents.stop(runID: id)
        case .sync: container.sync.cancel()
        }
        Task { try? await Task.sleep(for: .milliseconds(400)); await model.sample() }
    }
}

private struct ResourceRow: View {
    @Environment(AppContainer.self) private var container
    let node: ResourceNode
    let depth: Int
    @Binding var collapsed: Set<String>
    let onKill: (TrackedProcessKey) -> Void
    @State private var hovering = false

    private var isGroup: Bool { !node.children.isEmpty }
    private var isOpen: Bool { !collapsed.contains(node.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if isGroup {
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 12)
                } else {
                    Color.clear.frame(width: 12)
                }
                icon
                VStack(alignment: .leading, spacing: 0) {
                    Text(node.title).lineLimit(1)
                    if let subtitle = node.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if isGroup { Sparkline(values: node.history).frame(width: 44, height: 14).foregroundStyle(tint) }
                Text(ResourceFormatter.cpu(node.cpu)).frame(width: 64, alignment: .trailing)
                Text(ResourceFormatter.bytes(node.rss)).frame(width: 76, alignment: .trailing)
                killButton.frame(width: 22)
            }
            .font(.system(.callout, design: .monospaced)).monospacedDigit()
            .padding(.leading, 14 + CGFloat(depth) * 14).padding(.trailing, 14).padding(.vertical, 4)
            .background(hovering ? Color.primary.opacity(0.06) : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { if isGroup { toggle() } }

            if isGroup, isOpen {
                ForEach(node.children) { child in
                    ResourceRow(node: child, depth: depth + 1, collapsed: $collapsed, onKill: onKill)
                }
            }
        }
    }

    private func toggle() {
        if collapsed.contains(node.id) { collapsed.remove(node.id) } else { collapsed.insert(node.id) }
    }

    @ViewBuilder
    private var killButton: some View {
        if let key = node.processKey, hovering {
            Button { onKill(key) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                .buttonStyle(.borderless)
                .help("Detener")
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch node.kind {
        case .course: Circle().fill(tint).frame(width: 8, height: 8)
        case .scope: Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
        case .sync: Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
        case .process:
            if let provider = node.provider { AgentProviderMark(provider: provider, size: 13) }
            else { Image(systemName: "gearshape").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var tint: Color {
        guard node.kind == .course else { return .accentColor }
        return CoursePalette.color(for: Course(folderName: String(node.id.dropFirst("course:".count))))
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let top = max(values.max() ?? 1, 1)
            var path = Path()
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: size.width * Double(i) / Double(values.count - 1),
                                    y: size.height - size.height * v / top)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .foreground, lineWidth: 1.2)
        }
    }
}

private struct DiskSection: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let model = container.resources
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Espacio").font(.subheadline.weight(.semibold))
                Text("Beta").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Color.orange.opacity(0.14), in: Capsule())
                Spacer()
                if model.disk == .scanning { ProgressView().controlSize(.small) }
                Button("Escanear") { model.scanDisk() }
                    .controlSize(.small)
                    .disabled(model.disk == .scanning)
            }
            switch model.disk {
            case .idle:
                Text("No se ha escaneado el uso de disco").font(.callout).foregroundStyle(.secondary)
            case .scanning:
                Text("Escaneando…").font(.callout).foregroundStyle(.secondary)
            case .scanned(let summary, _):
                if summary.entries.isEmpty {
                    Text("No se encontraron materias en el espacio de trabajo.").font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Total").font(.callout.weight(.medium))
                        Spacer()
                        Text(ResourceFormatter.bytes(summary.total)).font(.system(.callout, design: .monospaced)).monospacedDigit()
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(summary.entries) { entry in
                                HStack {
                                    Circle().fill(CoursePalette.color(for: Course(folderName: entry.folder))).frame(width: 8, height: 8)
                                    Text(entry.displayName).lineLimit(1)
                                    Spacer()
                                    Text(ResourceFormatter.bytes(entry.bytes)).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                    }
                    .frame(maxHeight: 130)
                }
            }
        }
        .padding(14)
    }
}
