import Foundation
import Observation

/// State of the agent composer: text, caret, slash-command suggestions and prompt history.
/// UI-independent so the key handling in `ComposerTextView` and the SwiftUI popup share one source of truth.
@Observable @MainActor
final class ComposerModel {
    enum Accepted: Equatable {
        case inserted
        case execute(AppCommand)
    }

    static let maxSuggestions = 40

    var text = ""
    var selection = NSRange(location: 0, length: 0)
    var selectedIndex = 0
    var isDropTargeted = false
    var isFocused = false
    /// Height requested by the text view (already clamped to 1–8 lines).
    var contentHeight: CGFloat = 24
    var history = PromptHistory(entries: [])
    /// Provider whose commands the popup lists (titles of its sections).
    var provider: AgentProviderID = .claude

    /// Bumped on programmatic text changes so the AppKit view re-applies `text` and `selection`.
    private(set) var revision = 0
    /// Bumped to move keyboard focus into the text view.
    private(set) var focusToken = 0
    private(set) var sections: [SlashCommandSection] = []
    private(set) var flat: [SlashCommandMatch] = []
    private(set) var available: [SlashCommand] = []
    private var dismissed: NSRange?
    private var lastQuery: String?

    var isPopupVisible: Bool { !flat.isEmpty }
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var token: SlashToken? {
        guard selection.length == 0 else { return nil }
        return SlashToken.detect(in: text, caret: selection.location)
    }

    // MARK: - Updates from the text view

    func userEdited(text: String, selection: NSRange) {
        if text != self.text { history.reset() }
        self.text = text
        self.selection = selection
        refresh()
    }

    func selectionMoved(_ selection: NSRange) {
        guard selection != self.selection else { return }
        self.selection = selection
        refresh()
    }

    func setAvailable(_ commands: [SlashCommand]) {
        guard commands != available else { return }
        available = commands
        refresh()
    }

    // MARK: - Programmatic changes

    func setText(_ newText: String, caret: Int? = nil) {
        text = newText
        selection = NSRange(location: caret ?? (newText as NSString).length, length: 0)
        revision += 1
        refresh()
    }

    func requestFocus() { focusToken += 1 }

    func clear() {
        history.reset()
        setText("")
    }

    func insertReferences(_ references: [String]) {
        guard !references.isEmpty else { return }
        let result = ScopeRelativePath.insert(references, into: text, at: selection.location)
        setText(result.text, caret: result.caret)
        requestFocus()
    }

    // MARK: - Suggestions

    func moveSelection(by delta: Int) {
        guard !flat.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + flat.count) % flat.count
    }

    func dismissPopup() {
        dismissed = token?.range
        refresh()
    }

    /// Accepts the highlighted suggestion: inserts `/name ` or, for app commands without arguments, removes the
    /// token and asks the caller to execute the command.
    @discardableResult
    func acceptSelected() -> Accepted? {
        guard flat.indices.contains(selectedIndex), let token else { return nil }
        let command = flat[selectedIndex].command
        defer { requestFocus() }
        if command.kind == .app, !AppCommand.requiresArgument(command.name), let app = AppCommand.parse("/\(command.name)") {
            let remaining = (text as NSString).replacingCharacters(in: token.range, with: "")
            setText(remaining, caret: token.range.location)
            return .execute(app)
        }
        let result = token.replacing(in: text, with: command.name)
        setText(result.text, caret: result.caret)
        return .inserted
    }

    // MARK: - History

    func historyPrevious() -> Bool {
        guard let entry = history.previous(current: text) else { return false }
        setText(entry)
        return true
    }

    func historyNext() -> Bool {
        guard let entry = history.next() else { return false }
        setText(entry)
        return true
    }

    // MARK: - Internals

    private func refresh() {
        guard let token, token.range != dismissed else {
            if token == nil { dismissed = nil }
            sections = []; flat = []; lastQuery = nil; selectedIndex = 0
            return
        }
        let matches = SlashCommandMatcher.match(query: token.query, in: available, limit: Self.maxSuggestions)
        sections = SlashCommandCatalogPolicy.sections(from: matches, provider: provider)
        flat = sections.flatMap(\.matches)
        if lastQuery != token.query { selectedIndex = 0; lastQuery = token.query }
        selectedIndex = min(selectedIndex, max(0, flat.count - 1))
    }
}
