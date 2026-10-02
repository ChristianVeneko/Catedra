import SwiftUI
import AppKit

/// Rounded multi-line composer: editor, slash-command popup, model / permission chips, attach and send / stop.
struct AgentComposerView: View {
    let model: ComposerModel
    @Binding var options: AgentOptions
    let scopeFolder: URL
    let color: Color
    let hasRun: Bool
    let busy: Bool
    let send: (String) -> Void
    let stop: () -> Void
    let execute: (AppCommand) -> Void

    @State private var attachNotice: String?

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
                .alignmentGuide(.top) { $0[.bottom] + 8 }
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
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Adjuntar archivos de esta carpeta (@ruta)")
            Menu {
                ForEach(AgentModel.allCases) { item in
                    Button { options.model = item } label: {
                        if options.model == item { Label(item.label, systemImage: "checkmark") } else { Text(item.label) }
                    }
                }
            } label: { Chip(symbol: "cpu", text: options.model.label) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Modelo para esta conversación")
            Menu {
                ForEach(AgentPermissionMode.allCases) { item in
                    Button { options.permissionMode = item } label: {
                        if options.permissionMode == item { Label(item.label, systemImage: "checkmark") } else { Text(item.label) }
                    }
                }
            } label: {
                Chip(symbol: options.permissionMode == .bypassPermissions ? "exclamationmark.shield" : "lock.shield",
                     text: options.permissionMode.label,
                     tint: options.permissionMode == .bypassPermissions ? .orange : nil)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(options.permissionMode.detail)
            Spacer(minLength: 0)
            sendButton
        }
        .font(.callout)
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
            dropTargeted: { model.isDropTargeted = $0 })
    }

    private func accept() {
        if case .execute(let command) = model.acceptSelected() { execute(command) }
    }

    /// Enter / ⌘↩ / send button. While an agent runs the draft is kept.
    private func submit() {
        guard !model.isBlank, !busy else { return }
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.history.record(text)
        if let command = AppCommand.parse(text) {
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
        panel.message = "Elija archivos dentro de esta carpeta"
        let restriction = ScopeRestriction(base: scopeFolder)
        panel.delegate = restriction
        guard panel.runModal() == .OK else { return }
        insert(files: panel.urls)
        withExtendedLifetime(restriction) {}
    }

    private func insert(files: [URL]) {
        let references = files.compactMap { ScopeRelativePath.reference(for: $0, in: scopeFolder) }
        attachNotice = references.count < files.count ? "Solo se pueden adjuntar archivos dentro de esta carpeta." : nil
        model.insertReferences(references)
        if attachNotice != nil {
            Task { try? await Task.sleep(for: .seconds(4)); attachNotice = nil }
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

/// Keeps the attach panel's selectable items inside the scope folder.
private final class ScopeRestriction: NSObject, NSOpenSavePanelDelegate {
    private let basePath: String
    init(base: URL) { basePath = base.standardizedFileURL.resolvingSymlinksInPath().path }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == basePath || path.hasPrefix(basePath + "/")
    }
}
