import Foundation
import Observation

enum SidebarItem: Hashable {
    case today
    case all
    case activities(String)
    case contents(String)
    case forums(String)
    case agent(String)

    /// Folder name of the course this item belongs to, if any.
    var courseID: String? {
        switch self {
        case .activities(let id), .contents(let id), .forums(let id), .agent(let id): id
        case .today, .all: nil
        }
    }

    var showsActivities: Bool {
        switch self {
        case .today, .all, .activities: true
        case .contents, .forums, .agent: false
        }
    }
}

enum ActivityDetailTab: Hashable { case detail, agent }

@Observable @MainActor
final class NavigationModel {
    var activityTab: ActivityDetailTab = .detail
    var sidebar: SidebarItem? = .today
    var selectedActivityID: Activity.ID?
    var selectedNodeURL: URL?

    /// Jumps to the place where a run lives (activity agent tab or course agent view).
    func open(run: AgentRun, registry: AgentRunRegistry) {
        registry.selection[run.scope.id] = run.id
        switch run.scope.kind {
        case .course:
            sidebar = .agent(run.scope.folder)
        case .activity:
            sidebar = .activities(run.scope.courseFolderName)
            selectedActivityID = run.scope.folder
            activityTab = .agent
        }
    }
}
