import Foundation
import Observation

/// Detects edits to `enunciado.md` and to the dates of activities after each successful sync.
@Observable @MainActor
final class ChangeTrackingModel {
    private(set) var state = ChangeTrackingState()
    private var hasBaseline = false
    private let store: any StateStoring<ChangeTrackingState>
    private let notifier: AgentNotifying?
    private let notificationsEnabled: @MainActor () async -> Bool

    init(store: any StateStoring<ChangeTrackingState>, notifier: AgentNotifying? = nil,
         notificationsEnabled: @escaping @MainActor () async -> Bool = { false }) {
        self.store = store
        self.notifier = notifier
        self.notificationsEnabled = notificationsEnabled
    }

    func load() {
        if let stored = store.load() { state = stored; hasBaseline = true }
    }

    /// The unseen edit of an activity, if any.
    func change(for activityID: String) -> ActivityChange? {
        state.changes.first { $0.activityID == activityID && !$0.seen }
    }

    var unseenCount: Int { state.changes.filter { !$0.seen }.count }

    func markSeen(_ activityID: String) {
        state = ChangeDetector.markSeen(activityID, in: state)
        persist()
    }

    /// Takes the baseline on the first run; later runs record and announce edits.
    func process(snapshot: WorkspaceSnapshot, root: URL, now: Date = .now) async {
        let activities = snapshot.activities
        let tracked = await Task.detached { Self.track(activities, root: root) }.value
        let result = ChangeDetector.process(state: hasBaseline ? state : nil, current: tracked, now: now)
        state = result.state
        hasBaseline = true
        persist()
        guard !result.isBaseline, let content = ActivityChangeNotification.content(for: result.recorded) else { return }
        guard await notificationsEnabled() else { return }
        await notifier?.notifyFinished(title: content.title, body: content.body)
    }

    nonisolated static func track(_ activities: [Activity], root: URL) -> [TrackedActivity] {
        activities.map { activity in
            let file = root.appendingPathComponent(activity.folder, isDirectory: true).appendingPathComponent("enunciado.md")
            let text = (try? String(contentsOf: file, encoding: .utf8)).map(StatementNormalizer.normalize)
            return TrackedActivity(id: activity.id, name: activity.name, courseName: activity.courseName,
                                   snapshot: ActivitySnapshot(text: text, due: activity.due, opens: activity.opens, cutoff: activity.cutoff))
        }
    }

    private func persist() { try? store.save(state) }
}
