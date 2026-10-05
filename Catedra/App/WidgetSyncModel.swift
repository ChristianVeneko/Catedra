import Foundation
import Observation
import WidgetKit

/// Keeps the desktop widget's `widget-snapshot.json` current: rebuilds it whenever the activities, the review cards or
/// the focus timer change, and asks WidgetKit to reload (throttled) only when the content actually changed.
@MainActor
final class WidgetSyncModel {
    private let store: WidgetSnapshotStore
    private let build: @MainActor (Date) -> WidgetSnapshot
    private let reload: @MainActor () -> Void
    private let clock: @MainActor () -> Date
    private let debounce: Duration
    private var throttle: WidgetReloadThrottle
    private var lastWritten: WidgetSnapshot?
    private var pending: Task<Void, Never>?
    private var trailing: Task<Void, Never>?
    private var started = false

    init(store: WidgetSnapshotStore = .appGroup, debounce: Duration = .seconds(1),
         throttle: WidgetReloadThrottle = WidgetReloadThrottle(minimumInterval: 30),
         clock: @escaping @MainActor () -> Date = { .now },
         reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
         build: @escaping @MainActor (Date) -> WidgetSnapshot) {
        self.store = store
        self.debounce = debounce
        self.throttle = throttle
        self.clock = clock
        self.reload = reload
        self.build = build
    }

    /// Writes the first snapshot and then follows every change of the observable state read by `build`.
    func start() {
        guard !started else { return }
        started = true
        refresh()
        observe()
    }

    /// Rebuilds and, if the content changed, writes the file and reloads the timelines.
    func refresh() {
        let now = clock()
        let snapshot = build(now)
        if let lastWritten, lastWritten.hasSameContent(as: snapshot) { return }
        do { try store.write(snapshot) } catch { return }
        lastWritten = snapshot
        if throttle.shouldReload(now: now) { reload() } else { scheduleTrailingReload() }
    }

    /// A reload swallowed by the throttle still has to happen once the interval passes.
    private func scheduleTrailingReload() {
        guard trailing == nil else { return }
        trailing = Task { [weak self, interval = throttle.minimumInterval] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            trailing = nil
            _ = throttle.shouldReload(now: clock())
            reload()
        }
    }

    private func observe() {
        withObservationTracking {
            _ = build(clock())
        } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            refresh()
            observe()
        }
    }
}
