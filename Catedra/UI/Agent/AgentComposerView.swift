import SwiftUI
import AppKit

/// Rounded multi-line composer: editor, slash-command popup, model / permission chips, attach and send / stop.
struct AgentComposerView: View {
    let model: ComposerModel
    @Binding var options: AgentOptions
    let provider: AgentProviderID
    let models: [AgentModelOption]
    let scopeFolder: URL
    let color: Color
    let hasRun: Bool
    let busy: Bool
    let send: (String) -> Void
    let stop: () -> Void
    let execute: (AppCommand) -> Void

    @State private var attachNotice: String?
    @State private var showCustomModel = false
    @State private var customModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ComposerTextView(model: model,
                             placeholder: hasRun ? "Continúa la conversación o escribe / para comandos…"
                                                 : "Escribe una instrucción o / para comandos…",
                             revision: model.revision, focusToken: model.focusToken, handler: handler)
                .frame(height: model.contentHeight)
            controls
            if let attachNotice {
                Label(attachNotice, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(model.isDropTargeted ? color : (model.isFocused ? color.opacity(0.55) : Color.secondary.opacity(0.28)),
                              lineWidth: model.isDropTargeted ? 2 : 1)
        }
        .overlay(alignment: .top) {
            if model.isPopupVisible {
                SlashSuggestionPopup(model: model) { index in
                    model.selectedIndex = index
                    accept()
                }
                .offset(y: -(SlashSuggestionPopup.height(for: model) + 8))
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: model.isPopupVisible)
        .animation(.easeOut(duration: 0.12), value: model.contentHeight)
        .onReceive(NotificationCenter.default.publisher(for: .composerFocusChanged)) { note in
            model.isFocused = note.userInfo?["focused"] as? Bool ?? false
        }
    }

    // MARK: - Controls row

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: attach) { Image(systemName: "paperclip").font(.system(size: 14, weight: .medium)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Adjuntar archivos (@ruta). También puede arrastrarlos o pegarlos.")
            modelMenu
            Menu {
                ForEach(provider.supportedPermissions) { item in
                    Button { options.permission = item } label: {
                        if options.permission == item { Label(item.label, systemImage: "checkmark") } else { Text(item.label) }
                    }
                }
            } label: {
                Chip(symbol: options.permission == .unrestricted ? "exclamationmark.shield" : "lock.shield",
                     text: options.permission.label,
                     tint: options.permission == .unrestricted ? .orange : nil)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(options.permission.detail(for: provider))
            Spacer(minLength: 0)
            sendButton
        }
        .font(.callout)
    }

    // MARK: - Model chip

    private var allowsCustomModel: Bool {
        if case .listed(let allowsCustom) = provider.modelSource { allowsCustom } else { false }
    }

    private var modelLabel: String {
        guard let id = options.model else { return AgentModelOption.cliDefault.label }
        return models.first { $0.id == id }?.label ?? id
    }

    /// Models grouped by `provider/` prefix when the list is long (OpenCode can report hundreds).
    private var groupedModels: [(title: String, items: [AgentModelOption])]? {
        guard models.count > 16 else { return nil }
        let items = models.filter { $0.id != nil }
        let groups = Dictionary(grouping: items) { $0.id?.split(separator: "/").first.map(String.init) ?? "otros" }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    private func modelButton(_ item: AgentModelOption) -> some View {
        Button { options.model = item.id } label: {
            if options.model == item.id { Label(item.label, systemImage: "checkmark") } else { Text(item.label) }
        }
    }

    private var modelMenu: some View {
        Menu {
            if let groups = groupedModels {
                modelButton(.cliDefault)
                ForEach(groups, id: \.title) { group in
                    Menu(group.title) { ForEach(group.items) { modelButton($0) } }
                }
            } else {
                ForEach(models) { modelButton($0) }
            }
            if allowsCustomModel {
                Divider()
                Button("Otro modelo…") { customModel = options.model ?? ""; showCustomModel = true }
            }
        } label: { Chip(symbol: "cpu", text: modelLabel) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Modelo para esta conversación")
            .popover(isPresented: $showCustomModel, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modelo (proveedor/modelo)").font(.headline)
                    TextField("anthropic/claude-sonnet-4", text: $customModel)
                        .textFieldStyle(.roundedBorder).frame(width: 260)
                        .onSubmit(applyCustomModel)
                    HStack { Spacer(); Button("Usar", action: applyCustomModel).keyboardShortcut(.defaultAction) }
                }
                .padding(14)
            }
    }

    private func applyCustomModel() {
        let value = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        options.model = value.isEmpty ? nil : value
        showCustomModel = false
    }

    @ViewBuilder
    private var sendButton: some View {
        if busy {
            Button(action: stop) { Image(systemName: "stop.fill").font(.system(size: 12, weight: .bold)).frame(width: 26, height: 26) }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Circle().fill(Color.red))
                .help("Detener")
        } else {
            Button(action: submit) { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).frame(width: 26, height: 26) }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Circle().fill(model.isBlank ? Color.secondary.opacity(0.4) : color))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isBlank)
                .help("Enviar (↩)")
        }
    }

    // MARK: - Actions

    private var handler: ComposerHandler {
        ComposerHandler(
            isPopupVisible: { model.isPopupVisible },
            moveSelection: { model.moveSelection(by: $0) },
            accept: { accept() },
            dismissPopup: { model.dismissPopup() },
            send: { submit() },
            historyPrevious: { model.historyPrevious() },
            historyNext: { model.historyNext() },
            dropFiles: { insert(files: $0) },
            dropTargeted: { model.isDropTargeted = $0 },
            paste: { paste($0) })
    }

    private func accept() {
        if case .execute(let command) = model.acceptSelected() { execute(command) }
    }

    /// Enter / ⌘↩ / send button. While an agent runs the draft is kept.
    private func submit() {
        guard !model.isBlank, !busy else { return }
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.history.record(text)
        if let command = AppCommand.parse(text, provider: provider, models: models) {
            model.clear()
            execute(command)
        } else {
            model.clear()
            send(text)
        }
    }

    private func attach() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = scopeFolder
        panel.prompt = "Adjuntar"
        panel.message = "Elija los archivos que desea adjuntar"
        guard panel.runModal() == .OK else { return }
        insert(files: panel.urls)
    }

    private func insert(files: [URL]) {
        model.insertReferences(files.map { ScopeRelativePath.attachment(for: $0, in: scopeFolder) })
    }

    /// Files copied in Finder and images (screenshots) are attached; plain text falls through to the normal paste.
    private func paste(_ pasteboard: NSPasteboard) -> Bool {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let hasText = pasteboard.string(forType: .string) != nil
        let hasImage = pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
        switch PasteClassifier.classify(fileURLs: urls, hasImage: hasImage, hasText: hasText) {
        case .files(let files):
            insert(files: files)
            return true
        case .image:
            guard let png = PastedImageStore.pngData(from: pasteboard) else { return false }
            do {
                insert(files: [try PastedImageStore().save(png: png)])
            } catch {
                attachNotice = "No se pudo guardar la imagen pegada: \(error.localizedDescription)"
                Task { try? await Task.sleep(for: .seconds(4)); attachNotice = nil }
            }
            return true
        case .text:
            return false
        }
    }
}

/// Rounded label used by the model / permission menus.
private struct Chip: View {
    let symbol: String
    let text: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption)
            Text(text).font(.caption.weight(.medium))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
        }
        .foregroundStyle(tint ?? Color.secondary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background((tint ?? Color.secondary).opacity(0.12), in: Capsule())
    }
}
