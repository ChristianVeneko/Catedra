import SwiftUI
import AppKit

/// Keyboard and drop callbacks the AppKit text view needs from the composer.
struct ComposerHandler {
    var isPopupVisible: () -> Bool = { false }
    var moveSelection: (Int) -> Void = { _ in }
    var accept: () -> Void = {}
    var dismissPopup: () -> Void = {}
    var send: () -> Void = {}
    var historyPrevious: () -> Bool = { false }
    var historyNext: () -> Bool = { false }
    var dropFiles: ([URL]) -> Void = { _ in }
    var dropTargeted: (Bool) -> Void = { _ in }
    /// Offered every paste first; return true when it consumed the pasteboard (files / image), false for a text paste.
    var paste: (NSPasteboard) -> Bool = { _ in false }
}

/// Multi-line plain-text editor (1–10 lines, then scrolls) that owns Enter / Shift+Enter / Tab / Esc / arrow handling,
/// which SwiftUI's `TextEditor` cannot intercept reliably on macOS.
struct ComposerTextView: NSViewRepresentable {
    let model: ComposerModel
    let placeholder: String
    let revision: Int
    let focusToken: Int
    let handler: ComposerHandler

    static let font = NSFont.systemFont(ofSize: 14)
    static let verticalInset: CGFloat = 4
    static let maxLines = 10

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let textView = ComposerNSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.textColor = NSColor.labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: Self.verticalInset)
        textView.placeholder = placeholder
        textView.handler = handler
        textView.registerForDraggedTypes([.fileURL, .png, .tiff])
        textView.string = model.text
        textView.setSelectedRange(model.selection)

        let scroll = ComposerScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.appliedRevision = revision
        context.coordinator.appliedFocus = focusToken
        DispatchQueue.main.async { context.coordinator.reportHeight() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }
        textView.handler = handler
        textView.placeholder = placeholder
        if coordinator.appliedRevision != revision {
            coordinator.appliedRevision = revision
            coordinator.isApplying = true
            textView.string = model.text
            let length = (model.text as NSString).length
            let range = NSRange(location: min(model.selection.location, length), length: 0)
            textView.setSelectedRange(range)
            coordinator.isApplying = false
            textView.needsDisplay = true
            coordinator.reportHeight()
        }
        if coordinator.appliedFocus != focusToken {
            coordinator.appliedFocus = focusToken
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: ComposerModel
        weak var textView: ComposerNSTextView?
        var appliedRevision = 0
        var appliedFocus = 0
        var isApplying = false
        private var lastHeight: CGFloat = 0

        init(model: ComposerModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            model.userEdited(text: textView.string, selection: textView.selectedRange())
            reportHeight(deferred: false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            model.selectionMoved(textView.selectedRange())
        }

        /// Typing reports synchronously so the frame grows in the same pass as the new line; calls made during a
        /// SwiftUI update or AppKit layout must defer the state change.
        func reportHeight(deferred: Bool = true) {
            guard let textView else { return }
            let height = textView.clampedContentHeight()
            guard abs(height - lastHeight) > 0.5 else { return }
            lastHeight = height
            if deferred {
                DispatchQueue.main.async { [model] in model.contentHeight = height }
            } else {
                model.contentHeight = height
            }
        }
    }
}

/// Keeps the caret in view when SwiftUI resizes the editor: the text view scrolls to the caret before the new
/// height arrives, which would otherwise leave the first lines hidden or the caret below the visible area.
final class ComposerScrollView: NSScrollView {
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.height - frame.height) > 0.5
        super.setFrameSize(newSize)
        guard changed, let textView = documentView as? NSTextView else { return }
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

final class ComposerNSTextView: NSTextView {
    var handler = ComposerHandler()
    var placeholder = ""

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { NotificationCenter.default.post(name: .composerFocusChanged, object: self, userInfo: ["focused": true]) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { NotificationCenter.default.post(name: .composerFocusChanged, object: self, userInfo: ["focused": false]) }
        return accepted
    }

    override func layout() {
        super.layout()
        (delegate as? ComposerTextView.Coordinator)?.reportHeight()
    }

    override func paste(_ sender: Any?) {
        if handler.paste(NSPasteboard.general) { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if handler.paste(NSPasteboard.general) { return }
        super.pasteAsPlainText(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        if handler.paste(NSPasteboard.general) { return }
        super.pasteAsRichText(sender)
    }

    /// Screenshots (png/tiff only) and copied files carry no plain-text type, so a plain-text view would disable ⌘V.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        for type in [NSPasteboard.PasteboardType.png, .tiff, .fileURL] where !types.contains(type) { types.append(type) }
        return types
    }

    private static let pasteActions: Set<Selector> = [#selector(NSText.paste(_:)), #selector(NSTextView.pasteAsPlainText(_:)), #selector(NSTextView.pasteAsRichText(_:))]

    private var pasteboardHasAttachable: Bool {
        let pasteboard = NSPasteboard.general
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return true }
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, Self.pasteActions.contains(action), isEditable, pasteboardHasAttachable { return true }
        return super.validateUserInterfaceItem(item)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let action = menuItem.action, Self.pasteActions.contains(action), isEditable, pasteboardHasAttachable { return true }
        return super.validateMenuItem(menuItem)
    }

    // MARK: Placeholder and sizing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: ComposerTextView.font, .foregroundColor: NSColor.placeholderTextColor])
    }

    func clampedContentHeight() -> CGFloat {
        guard let layoutManager, let textContainer else { return 24 }
        layoutManager.ensureLayout(for: textContainer)
        let line = layoutManager.defaultLineHeight(for: ComposerTextView.font)
        let inset = textContainerInset.height * 2
        let used = layoutManager.usedRect(for: textContainer).height
        let content = max(used, line) + inset
        return min(content, line * CGFloat(ComposerTextView.maxLines) + inset)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard !hasMarkedText() else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let popup = handler.isPopupVisible()
        switch event.keyCode {
        case 126: // up
            if popup { handler.moveSelection(-1); return }
            if flags.isEmpty, selectedRange().length == 0, caretOnFirstLine, handler.historyPrevious() { return }
        case 125: // down
            if popup { handler.moveSelection(1); return }
            if flags.isEmpty, selectedRange().length == 0, caretOnLastLine, handler.historyNext() { return }
        case 48: // tab
            if popup, flags.isEmpty { handler.accept(); return }
        case 36, 76: // return, keypad enter
            if flags.contains(.shift) || flags.contains(.option) { insertNewline(nil); return }
            if popup, flags.isEmpty { handler.accept(); return }
            handler.send()
            return
        case 53: // escape
            if popup { handler.dismissPopup() } else { window?.makeFirstResponder(nil) }
            return
        default: break
        }
        super.keyDown(with: event)
    }

    private var caretOnFirstLine: Bool {
        guard let layoutManager, layoutManager.numberOfGlyphs > 0 else { return true }
        var glyphRange = NSRange()
        _ = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &glyphRange)
        let chars = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let caret = selectedRange().location
        let ns = string as NSString
        if caret == NSMaxRange(chars), caret > 0, ns.character(at: caret - 1) == 0x0A { return false }
        return caret <= NSMaxRange(chars)
    }

    private var caretOnLastLine: Bool {
        let ns = string as NSString
        let caret = selectedRange().location
        guard ns.length > 0, let layoutManager, layoutManager.numberOfGlyphs > 0 else { return true }
        if ns.character(at: ns.length - 1) == 0x0A { return caret == ns.length }
        var glyphRange = NSRange()
        _ = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: &glyphRange)
        let chars = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        return caret >= chars.location
    }

    // MARK: Drag and drop of files from Finder

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return super.draggingEntered(sender) }
        handler.dropTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        handler.dropTargeted(false)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        handler.dropTargeted(false)
        handler.dropFiles(urls)
        return true
    }
}

extension Notification.Name {
    static let composerFocusChanged = Notification.Name("CatedraComposerFocusChanged")
}
