import SwiftUI
import AppKit
import QuickLook

/// Chat-like agent panel for one scope (activity or course).
struct AgentPanelView: View {
    @Environment(AppContainer.self) private var container
    let scope: AgentScope
    let color: Color

    @State private var draft = ""
    @State private var options = AgentOptions()
    @State private var pendingRecipe: Recipe?
    @State private var recipeText = ""
    @State private var generated: [URL] = []
    @State private var quickLookURL: URL?

    private var registry: AgentRunRegistry { container.agents }
    private var run: AgentRun? { registry.selectedRun(in: scope.id) }
    private var busy: Bool { registry.isRunning(scopeID: scope.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let error = registry.startErrors[scope.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let run, !run.isRunning {
                GeneratedFilesSection(files: generated, preview: { quickLookURL = $0 })
            }
            if let run { AgentFooter(run: run) }
            Divider()
            composer
        }
        .quickLookPreview($quickLookURL, in: generated)
        .onAppear { options = AgentOptions(model: container.settings.agentModel, permissionMode: container.settings.agentPermissionMode) }
        .task(id: ScanKey(runID: run?.id, finished: run?.finishedAt, running: run?.isRunning ?? false)) { await scanGenerated() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(color)
            Text(run?.title ?? "Nueva conversación").font(.headline).lineLimit(1)
            if let run { StatusPill(status: run.status) }
            Spacer()
            historyMenu
            Button { registry.selection[scope.id] = nil; pendingRecipe = nil } label: { Label("Nueva", systemImage: "plus.bubble") }
                .disabled(busy || (run == nil && pendingRecipe == nil))
                .help("Nueva conversación")
            Button { registry.openInTerminal(scope: scope, run: run) } label: { Label("Abrir en Terminal", systemImage: "terminal") }
                .help("Continuar esta conversación en Terminal")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var historyMenu: some View {
        let history = registry.runs(in: scope.id)
        return Menu {
            if history.isEmpty { Text("Sin historial") }
            ForEach(history) { item in
                Button {
                    registry.selection[scope.id] = item.id
                    pendingRecipe = nil
                } label: {
                    Label("\(item.title) · \(Formatters.relative(item.startedAt))", systemImage: item.status.symbol)
                }
            }
        } label: { Label("Historial", systemImage: "clock.arrow.circlepath") }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(history.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if let recipe = pendingRecipe, run == nil {
            ScrollView {
                RecipePromptEditor(recipe: recipe, text: $recipeText, color: color, run: runRecipe) { pendingRecipe = nil }
            }
        } else if let run {
            AgentTranscriptView(items: TranscriptItem.build(from: run.transcript), color: color, isRunning: run.isRunning)
        } else {
            RecipeGalleryView(scope: scope, recipes: RecipeCatalog.recipes(for: scope), color: color) { recipe in
                recipeText = RecipeCatalog.render(recipe, scope: scope, activities: courseActivities, formatDate: Formatters.due)
                pendingRecipe = recipe
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(run == nil ? "Escriba una instrucción para el agente…" : "Continuar la conversación…",
                          text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(busy)
                if busy, let run {
                    Button { registry.stop(runID: run.id) } label: { Label("Detener", systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    Button(action: send) { Label("Enviar", systemImage: "arrow.up.circle.fill") }
                        .buttonStyle(.borderedProminent).tint(color)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Enviar (⌘↩)")
                }
            }
            HStack(spacing: 14) {
                Picker("Modelo", selection: $options.model) {
                    ForEach(AgentModel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).fixedSize()
                Picker("Permisos", selection: $options.permissionMode) {
                    ForEach(AgentPermissionMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).fixedSize()
                .help(options.permissionMode.detail)
                if options.permissionMode == .bypassPermissions {
                    Label("El agente podrá ejecutar cualquier acción sin pedir permiso.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
            }
            .font(.callout)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Actions

    private var courseActivities: [Activity] {
        if case .course(let course) = scope { return container.workspace.activities(in: course) }
        return []
    }

    private func send() {
        let text = draft
        let continuing = (run?.sessionId != nil) ? run?.id : nil
        registry.start(scope: scope, prompt: text, recipe: nil, options: options, continuing: continuing)
        draft = ""
    }

    private func runRecipe() {
        guard let recipe = pendingRecipe else { return }
        registry.start(scope: scope, prompt: recipeText, recipe: recipe, options: options)
        pendingRecipe = nil
    }

    private struct ScanKey: Hashable { let runID: UUID?; let finished: Date?; let running: Bool }

    private func scanGenerated() async {
        guard let run, !run.isRunning else { generated = []; return }
        let folder = scope.url(in: container.settings.workspaceURL)
        let since = run.startedAt
        generated = await Task.detached { GeneratedFilesScanner.scan(folder: folder, since: since) }.value
    }
}

struct StatusPill: View {
    let status: AgentRun.Status
    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.14), in: Capsule())
    }
}

private struct AgentFooter: View {
    let run: AgentRun

    var body: some View {
        HStack(spacing: 14) {
            StatusPill(status: run.status)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let end = run.finishedAt ?? context.date
                Label(AgentFormat.elapsed(end.timeIntervalSince(run.turnStartedAt)), systemImage: "timer").monospacedDigit()
            }
            if run.costUSD > 0 { Label(AgentFormat.cost(run.costUSD), systemImage: "dollarsign.circle").monospacedDigit() }
            if let model = run.model { Label(model, systemImage: "cpu").lineLimit(1) }
            Spacer()
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.vertical, 6)
    }
}

private struct GeneratedFilesSection: View {
    let files: [URL]
    let preview: (URL) -> Void
    @State private var expanded = true

    var body: some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                DisclosureGroup(isExpanded: $expanded) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(files, id: \.self) { url in
                                FileRow(url: url, preview: { preview(url) })
                                if url != files.last { Divider().padding(.leading, 46) }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .card()
                } label: {
                    Label("Archivos generados (\(files.count))", systemImage: "doc.badge.plus").font(.callout.weight(.semibold))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
}
