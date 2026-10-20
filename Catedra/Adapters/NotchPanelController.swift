import AppKit
import SwiftUI

/// Borderless, non-activating panel pinned to the top center of the screen with a notch (or the main screen), above
/// the menu bar, on every Space and next to full-screen apps. It never takes focus from the app being presented.
/// While visible it owns the teleprompter's global hotkeys.
@MainActor
final class NotchPanelController: TeleprompterPresenting {
    static let size = NSSize(width: 680, height: 200)

    private var panel: NSPanel?
    private weak var model: TeleprompterModel?
    private let hotKeys = GlobalHotKeys()

    func attach(model: TeleprompterModel) { self.model = model }

    func show() {
        guard let model, let screen = Self.targetScreen() else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.sharingType = model.hiddenFromCapture ? .none : .readOnly
        let notchHeight = screen.safeAreaInsets.top
        // A fresh root view replays the opening animation.
        let island = TeleprompterIslandView(model: model, notchHeight: notchHeight) { [weak self] height in
            self?.resize(height: height)
        }
        let hosting = NSHostingView(rootView: island)
        // The panel keeps the frame set below; the SwiftUI content must not resize it to its ideal size.
        hosting.sizingOptions = []
        panel.contentView = hosting
        let width = max(Self.size.width, Self.notchWidth(of: screen) + 260)
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - Self.size.height - notchHeight,
                           width: width, height: Self.size.height + notchHeight)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        registerHotKeys()
    }

    func hide() {
        hotKeys.unregisterAll()
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    // MARK: - Internals

    /// Keeps the top edge pinned while the island grows or shrinks.
    private func resize(height: CGFloat) {
        guard let panel, height > 1, abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        hotKeys.register([
            .init(key: .space) { [weak self] in self?.model?.togglePause() },
            .init(key: .left) { [weak self] in self?.model?.previousSentence() },
            .init(key: .right) { [weak self] in self?.model?.nextSentence() },
            .init(key: .up) { [weak self] in self?.model?.previousSection() },
            .init(key: .down) { [weak self] in self?.model?.nextSection() },
            .init(key: .equal) { [weak self] in self?.adjustFont(by: 2) },
            .init(key: .minus) { [weak self] in self?.adjustFont(by: -2) },
            .init(key: .escape) { [weak self] in self?.model?.close() },
        ])
    }

    private func adjustFont(by delta: Double) {
        guard let model else { return }
        model.fontSize = min(max(model.fontSize + delta, 14), 40)
    }

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func notchWidth(of screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return 0 }
        return max(0, screen.frame.width - left.width - right.width)
    }
}

/// AppKit keeps ordinary windows below the menu bar; the island must sit flush with the top edge, inside the notch.
private final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
