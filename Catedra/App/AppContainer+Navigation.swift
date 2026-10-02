import AppKit
import Foundation

/// Cross-cutting navigation: bringing the main window forward and executing palette actions.
extension AppContainer {
    static let mainWindowID = "main"

    func showMainWindow() {
        openWindowByID?(Self.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(Self.mainWindowID) == true }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Shows the main window on an activity (notification tap, menu bar "Abrir", palette).
    func reveal(activityID: String) {
        guard let activity = workspace.activity(id: activityID) else { showMainWindow(); return }
        reveal(activity: activity)
    }

    func reveal(activity: Activity) {
        workspace.searchText = ""
        navigation.show(activity: activity)
        showMainWindow()
    }

    /// Course the user is looking at (sidebar course item or selected activity).
    var currentCourse: Course? {
        if let id = navigation.sidebar?.courseID { return workspace.snapshot.courses.first { $0.id == id } }
        return workspace.activity(id: navigation.selectedActivityID).flatMap { workspace.course(for: $0) }
    }

    /// Background sync on launch, subject to `LaunchSyncPolicy`. Never runs under tests or with
    /// `CATEDRA_DISABLE_LAUNCH_SYNC=1`.
    func startLaunchSyncIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        let disabled = env["CATEDRA_DISABLE_LAUNCH_SYNC"] == "1" || env["XCTestConfigurationFilePath"] != nil
        sync.startOnLaunchIfNeeded(onboardingCompleted: UserDefaults.standard.bool(forKey: OnboardingModel.Keys.completed),
                                   disabledByEnvironment: disabled)
    }

    func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func wirePalette() {
        palette.itemsProvider = { [weak self] in
            guard let self else { return [] }
            return PaletteCatalog.items(activities: workspace.allActivitiesSorted, courses: workspace.snapshot.courses,
                                        contents: contentIndex.entries, provider: settings.agentProvider)
        }
        palette.recipeProvider = { [weak self] query in
            guard let self else { return [] }
            let now = Date.now
            return PaletteCatalog.recipeItems(
                query: query, activities: workspace.allActivitiesSorted, courses: workspace.snapshot.courses,
                contextActivity: workspace.activity(id: navigation.selectedActivityID), contextCourse: currentCourse,
                stateOf: { self.workspace.state(of: $0, now: now) }, now: now)
        }
        palette.onPresent = { [weak self] in self?.contentIndex.refreshIfNeeded() }
        palette.perform = { [weak self] action in self?.perform(action) }
    }

    func perform(_ action: PaletteAction) {
        workspace.searchText = ""
        switch action {
        case .openActivity(let id):
            reveal(activityID: id)
        case .openCourse(let folder):
            navigation.sidebar = .activities(folder)
        case .openCourseAgent(let folder):
            navigation.sidebar = .agent(folder)
        case .openContent(let folder, let path):
            navigation.show(content: URL(fileURLWithPath: path), courseFolder: folder)
        case .sync(let includeFiles):
            sync.start(includeFiles: includeFiles)
        case .openSettings:
            openSettingsWindow()
        case .openOnboarding:
            openWindowByID?("onboarding")
        case .showToday:
            navigation.sidebar = .today
        case .setProvider(let provider):
            settings.agentProvider = provider
            Task { await settings.refreshStatus(provider) }
        case .runRecipe(let recipeID, let folder, let isCourse):
            guard let recipe = RecipeCatalog.recipe(id: recipeID) else { return }
            if isCourse, let course = workspace.snapshot.courses.first(where: { $0.folderName == folder }) {
                navigation.show(recipe: recipe, scope: .course(course))
            } else if let activity = workspace.activity(id: folder) {
                navigation.show(recipe: recipe, scope: .activity(activity))
            }
        }
    }
}
