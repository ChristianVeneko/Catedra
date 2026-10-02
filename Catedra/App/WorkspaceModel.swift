import Foundation
import Observation

@Observable @MainActor
final class WorkspaceModel {
    private(set) var snapshot: WorkspaceSnapshot = .empty
    private(set) var loadError: String?
    private(set) var isLoading = false
    var searchText = ""

    let settings: SettingsModel
    let reader: WorkspaceReading
    private let loadUseCase: LoadWorkspaceUseCase
    private let watcher = WorkspaceWatcher()
    private var watchedRoot: URL?

    init(settings: SettingsModel, reader: WorkspaceReading) {
        self.settings = settings
        self.reader = reader
        self.loadUseCase = LoadWorkspaceUseCase(reader: reader)
    }

    var root: URL { settings.workspaceURL }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await loadUseCase.execute(root: root)
            loadError = nil
        } catch {
            loadError = "No se pudo leer el espacio de trabajo: \(error.localizedDescription)"
        }
        startWatchingIfNeeded()
    }

    private func startWatchingIfNeeded() {
        guard watchedRoot != root else { return }
        watchedRoot = root
        watcher.start(root: root) { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
    }

    // MARK: - Queries

    func course(for activity: Activity) -> Course? {
        snapshot.courses.first { $0.folderName == activity.courseFolderName }
    }

    func state(of activity: Activity, now: Date = .now) -> ActivityState {
        ActivityState.derive(from: activity, hasUserWork: snapshot.activitiesWithUserWork.contains(activity.id), now: now)
    }

    func activity(id: Activity.ID?) -> Activity? {
        guard let id else { return nil }
        return snapshot.activities.first { $0.id == id }
    }

    func activities(in course: Course) -> [Activity] {
        sortedByDue(snapshot.activities.filter { $0.courseFolderName == course.folderName })
    }

    var allActivitiesSorted: [Activity] { sortedByDue(snapshot.activities) }

    var searchResults: [Activity] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allActivitiesSorted.filter {
            $0.name.localizedStandardContains(q) || $0.courseName.localizedStandardContains(q)
        }
    }

    func agenda(now: Date) -> Agenda {
        Agenda.build(activities: snapshot.activities, stateOf: { state(of: $0, now: now) }, now: now, calendar: Formatters.calendar)
    }

    private func sortedByDue(_ items: [Activity]) -> [Activity] {
        items.sorted {
            switch ($0.due, $1.due) {
            case let (a?, b?): a < b
            case (_?, nil): true
            case (nil, _?): false
            default: $0.name < $1.name
            }
        }
    }
}
