import Foundation

/// Shell-style history of sent prompts: previous/next walk through entries and finally back to the unsent draft.
struct PromptHistory: Equatable, Sendable {
    private(set) var entries: [String]
    private var cursor: Int?
    private var draft = ""

    init(entries: [String]) { self.entries = entries }

    /// Older entry, remembering `current` as the draft the first time. Nil when there is nothing to show.
    mutating func previous(current: String) -> String? {
        guard !entries.isEmpty else { return nil }
        let next: Int
        if let cursor { next = max(0, cursor - 1) } else { draft = current; next = entries.count - 1 }
        cursor = next
        return entries[next]
    }

    /// Newer entry; after the newest one it restores the draft. Nil when not navigating.
    mutating func next() -> String? {
        guard let cursor else { return nil }
        if cursor + 1 < entries.count {
            self.cursor = cursor + 1
            return entries[cursor + 1]
        }
        self.cursor = nil
        return draft
    }

    var isNavigating: Bool { cursor != nil }

    mutating func record(_ prompt: String) {
        cursor = nil
        if entries.last != prompt { entries.append(prompt) }
    }

    mutating func reset() { cursor = nil }

    /// Free-form prompts of the given runs, oldest first. A recipe's first prompt is a template, not something typed.
    static func entries(from runs: [AgentRun]) -> [String] {
        var result: [String] = []
        for run in runs.sorted(by: { $0.startedAt < $1.startedAt }) {
            var first = true
            for event in run.transcript {
                guard case .userPrompt(let text) = event else { continue }
                defer { first = false }
                if first, run.recipeID != nil { continue }
                if result.last != text { result.append(text) }
            }
        }
        return result
    }
}
