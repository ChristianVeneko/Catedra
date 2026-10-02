import Foundation
import Observation

enum SidebarItem: Hashable {
    case today
    case all
    case activities(String)
    case contents(String)
    case forums(String)

    var showsActivities: Bool {
        switch self {
        case .today, .all, .activities: true
        case .contents, .forums: false
        }
    }
}

@Observable @MainActor
final class NavigationModel {
    var sidebar: SidebarItem? = .today
    var selectedActivityID: Activity.ID?
    var selectedNodeURL: URL?
}
