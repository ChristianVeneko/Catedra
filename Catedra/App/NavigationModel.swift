import Foundation
import Observation

enum SidebarItem: Hashable {
    case today
    case calendar
    case grades
    case all
    case activities(String)
    case contents(String)
    case forums(String)
    case agent(String)

    /// Folder name of the course this item belongs to, if any.
    var courseID: String? {
        switch self {
        case .activities(let id), .contents(let id), .forums(let id), .agent(let id): id
        case .today, .calendar, .grades, .all: nil
        }
    }

    var showsActivities: Bool {
        switch self {
        case .today, .all, .activities: true
        case .calendar, .grades, .contents, .forums, .agent: false
        }
    }
}

enum ActivityDetailTab: Hashable { case detail, agent }

/// A recipe chosen elsewhere (command palette) that the agent panel of `scopeID` should prefill, without running it.
struct PendingRecipe: Equatable {
    let recipeID: String
    let scopeID: String
}

@Observable @MainActor
final class NavigationModel {
    var activityTab: ActivityDetailTab = .detail
    var sidebar: SidebarItem? = .today
    var selectedActivityID: Activity.ID?
    var selectedNodeURL: URL?
    var pendingRecipe: PendingRecipe?

    func show(activity: Activity) {
        sidebar = .activities(activity.courseFolderName)
        selectedActivityID = activity.id
        activityTab = .detail
    }

    func show(content url: URL, courseFolder: String) {
        sidebar = .contents(courseFolder)
        selectedNodeURL = url
    }

    /// Opens the agent panel of an activity or course so it can prefill `recipe`.
    func show(recipe: Recipe, scope: AgentScope) {
        pendingRecipe = PendingRecipe(recipeID: recipe.id, scopeID: scope.id)
        switch scope {
        case .course(let course):
            sidebar = .agent(course.folderName)
        case .activity(let activity):
            sidebar = .activities(activity.courseFolderName)
            selectedActivityID = activity.id
            activityTab = .agent
        }
    }

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
