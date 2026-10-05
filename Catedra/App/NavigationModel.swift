import Foundation
import Observation

enum SidebarItem: Hashable {
    case today
    case calendar
    case grades
    case review
    case all
    case activities(String)
    case contents(String)
    case forums(String)
    case agent(String)

    /// Folder name of the course this item belongs to, if any.
    var courseID: String? {
        switch self {
        case .activities(let id), .contents(let id), .forums(let id), .agent(let id): id
        case .today, .calendar, .grades, .review, .all: nil
        }
    }

    var showsActivities: Bool {
        switch self {
        case .today, .all, .activities: true
        case .calendar, .grades, .review, .contents, .forums, .agent: false
        }
    }
}

enum ActivityDetailTab: Hashable { case detail, agent }

/// A recipe chosen elsewhere (command palette) that the agent panel of `scopeID` should prefill, without running it.
struct PendingRecipe: Equatable {
    let recipeID: String
    let scopeID: String
}

/// Files that the agent panel of `scopeID` should insert as references into its composer.
struct PendingAttachments: Equatable {
    let scopeID: String
    let files: [URL]
}

/// File opened from a full-text result; `page` applies to PDFs only.
struct ContentTarget: Equatable {
    let url: URL
    let page: Int?
}

@Observable @MainActor
final class NavigationModel {
    var activityTab: ActivityDetailTab = .detail
    var sidebar: SidebarItem? = .today
    var selectedActivityID: Activity.ID?
    var selectedNodeURL: URL?
    var pendingRecipe: PendingRecipe?
    var pendingAttachments: PendingAttachments?
    private(set) var contentTarget: ContentTarget?

    /// Page to open `url` at, when it is the file the last full-text result pointed to.
    func initialPage(for url: URL) -> Int? { contentTarget?.url == url ? contentTarget?.page : nil }

    func show(activity: Activity) {
        sidebar = .activities(activity.courseFolderName)
        selectedActivityID = activity.id
        activityTab = .detail
    }

    func show(content url: URL, courseFolder: String, page: Int? = nil) {
        sidebar = .contents(courseFolder)
        contentTarget = page.map { ContentTarget(url: url, page: $0) }
        selectedNodeURL = url
    }

    /// Opens the course agent so its composer receives `files` as references.
    func show(attachments files: [URL], in course: Course) {
        let scope = AgentScope.course(course)
        pendingAttachments = PendingAttachments(scopeID: scope.id, files: files)
        sidebar = .agent(course.folderName)
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
