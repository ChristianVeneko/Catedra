import SwiftUI
import AppKit
import QuickLook

/// Chat-like agent panel for one scope (activity or course).
struct AgentPanelView: View {
    @Environment(AppContainer.self) private var container
    let scope: AgentScope
    let color: Color

    @State private var composer = ComposerModel()
    @State private var notice: String?
    @State private var showResume = false
    @State private var showFiles = false
    @State private var sheetFiles: [URL] = []
    @State private var options = AgentOptions()
    @State private var pendingRecipe: Recipe?
    @State private var recipeText = ""
    @State private var generated: [URL] = []
    @State private var quickLookURL: URL?

    private var registry: AgentRunRegistry { container.agents }
    private var run: AgentRun? { registry.selectedRun(in: scope.id) }
    private var busy: Bool { registry.isRunning(scopeID: scope.id) }
    /// Provider of the open conversation, or the default one for a new conversation.
    private var activeProvider: AgentProviderID { run?.provider ?? container.settings.agentProvider }

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
            composerBar
        }
        .quickLookPreview($quickLookURL, in: generated)
        .onAppear {
            options = container.settings.defaultOptions(for: activeProvider)
            composer.provider = activeProvider
            composer.history = PromptHistory(entries: registry.promptHistory(in: scope.id))
            composer.setAvailable(availableCommands)
        }
        .task(id: PrepareKey(scopeID: scope.id, provider: activeProvider)) {
            await container.commands.prepare(folder: scopeFolder, provider: activeProvider)
        }
        .onChange(of: activeProvider) { _, provider in
            options = container.settings.defaultOptions(for: provider)
            composer.provider = provider
            composer.setAvailable(availableCommands)
        }
        .onChange(of: availableCommands) { _, commands in composer.setAvailable(commands) }
        .sheet(isPresented: $showResume) {
            ResumePickerSheet(scope: scope, runs: registry.runs, pick: resume, cancel: { showResume = false })
        }
        .sheet(isPresented: $showFiles) {
            GeneratedFilesSheet(files: sheetFiles, preview: { quickLookURL = $0 }, close: { showFiles = false })
        }
        .task(id: ScanKey(runID: run?.id, finished: run?.finishedAt, running: run?.isRunning ?? false)) { await scanGenerated() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            AgentProviderMark(provider: activeProvider, size: 18)
            Text(run?.title ?? "Nueva conversación").font(.headline).lineLimit(1)
            if let run { StatusPill(status: run.status) }
            Spacer()
            historyMenu
            Button { registry.selection[scope.id] = nil; pendingRecipe = nil } label: { Label("Nueva", systemImage: "plus.bubble") }
                .disabled(busy || (run == nil && pendingRecipe == nil))
                .help("Nueva conversación")
            Button { registry.openInTerminal(scope: scope, run: run) } label: { Label("Abrir en Terminal", systemImage: "terminal") }
                .help("Continuar esta conversación en Terminal con \(activeProvider.displayName)")
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
                    Label("\(item.title) · \(Formatters.relative(item.startedAt)) · \(item.provider.displayName)", systemImage: item.status.symbol)
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
            AgentTranscriptView(items: TranscriptItem.build(from: run.transcript), color: color, isRunning: run.isRunning,
                                provider: run.provider)
        } else {
            RecipeGalleryView(scope: scope, provider: activeProvider, recipes: RecipeCatalog.recipes(for: scope), color: color) { recipe in
                recipeText = RecipeCatalog.render(recipe, scope: scope, activities: courseActivities, formatDate: Formatters.due)
                pendingRecipe = recipe
            }
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice {
                Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            AgentComposerView(model: composer, options: $options, provider: activeProvider,
                              models: container.settings.modelOptions(for: activeProvider), scopeFolder: scopeFolder, color: color,
                              hasRun: run != nil, busy: busy,
                              send: send, stop: { if let run { registry.stop(runID: run.id) } },
                              execute: execute)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .animation(.easeOut(duration: 0.15), value: notice)
    }

    // MARK: - Actions

    private var courseActivities: [Activity] {
        if case .course(let course) = scope { return container.workspace.activities(in: course) }
        return []
    }

    private var scopeFolder: URL { scope.url(in: container.settings.workspaceURL) }
    private var availableCommands: [SlashCommand] { container.commands.commands(in: scopeFolder, provider: activeProvider) }

    private func send(_ text: String) {
        let continuing = (run?.sessionId != nil) ? run?.id : nil
        registry.start(scope: scope, prompt: text, recipe: nil, options: options, continuing: continuing)
    }

    private func execute(_ command: AppCommand) {
        switch command {
        case .resume:
            showResume = true
        case .newConversation, .recipes:
            guard !busy else { return show("Espere a que termine el agente antes de cambiar de conversación.") }
            registry.selection[scope.id] = nil
            pendingRecipe = nil
            composer.requestFocus()
        case .setModel(let model):
            options.model = model
            let label = container.settings.modelOptions(for: activeProvider).first { $0.id == model }?.label ?? model ?? "Predeterminado"
            show("Modelo de esta conversación: \(label).")
        case .setPermission(let level):
            options.permission = level
            show("Permisos: \(level.label).")
        case .terminal:
            registry.openInTerminal(scope: scope, run: run)
        case .files:
            let folder = scopeFolder
            let since = run?.startedAt
            Task {
                sheetFiles = await Task.detached { since.map { GeneratedFilesScanner.scan(folder: folder, since: $0) } ?? [] }.value
                showFiles = true
            }
        case .invalid(let message):
            show(message)
        }
    }

    private func resume(_ picked: AgentRun) {
        showResume = false
        guard !busy || picked.scope.id != scope.id else { return show("Espere a que termine el agente antes de cambiar de conversación.") }
        if picked.scope.id == scope.id {
            registry.selection[scope.id] = picked.id
            pendingRecipe = nil
            composer.requestFocus()
        } else {
            container.navigation.open(run: picked, registry: registry)
        }
        if picked.sessionId == nil { show("Esta conversación no tiene sesión guardada; el siguiente mensaje empezará una nueva.") }
    }

    private func show(_ message: String) {
        notice = message
        Task { try? await Task.sleep(for: .seconds(5)); if notice == message { notice = nil } }
    }

    private func runRecipe() {
        guard let recipe = pendingRecipe else { return }
        registry.start(scope: scope, prompt: recipeText, recipe: recipe, options: options)
        pendingRecipe = nil
    }

    private struct PrepareKey: Hashable { let scopeID: String; let provider: AgentProviderID }
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
            if run.costUSD > 0 {
                Label(AgentFormat.cost(run.costUSD), systemImage: "dollarsign.circle").monospacedDigit()
            } else if run.inputTokens + run.outputTokens > 0 {
                Label(AgentFormat.tokens(input: run.inputTokens, output: run.outputTokens), systemImage: "number.circle").monospacedDigit()
            }
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
