import Foundation
import Observation
import UserNotifications

/// Composition root: wires adapters into use cases and view models.
@Observable @MainActor
final class AppContainer {
    let settings: SettingsModel
    let workspace: WorkspaceModel
    let navigation = NavigationModel()
    let sync: SyncModel
    let reader: WorkspaceReading
    let importFiles: ImportFilesUseCase
    let agents: AgentRunRegistry
    let resources: ResourceMonitorModel
    let commands: SlashCommandCatalog
    let onboarding: OnboardingModel
    let clock = MinuteClock()
    let reminders: ReminderModel
    let contentIndex: ContentIndexModel
    let searchIndex: SearchIndexModel
    let palette = PaletteModel()
    let planner = CalendarModel()
    let grades = GradesModel()
    let review = ReviewModel()
    let notificationRouter = NotificationRouter()
    let changes: ChangeTrackingModel
    let focus: FocusTimerModel
    let weekly: WeeklySummaryModel
    let autopilot: AutopilotModel
    let teleprompter: TeleprompterModel
    let notchPanel = NotchPanelController()
    var widget: WidgetSyncModel?
    /// Opens a window scene by id; registered by views that have access to `openWindow`.
    var openWindowByID: (@MainActor (String) -> Void)?

    init() {
        // Under tests (or with CATEDRA_SKIP_KEYCHAIN=1) never touch the Keychain: a fresh ad-hoc signature would trigger
        // a blocking access prompt.
        let env = ProcessInfo.processInfo.environment
        let skipKeychain = env["XCTestConfigurationFilePath"] != nil || env["CATEDRA_SKIP_KEYCHAIN"] == "1"
        let credentials: CredentialStoring = skipKeychain ? EmptyCredentialStore() : KeychainCredentialStore()
        let reader = FileSystemWorkspace()
        let settings = SettingsModel(store: credentials)
        let workspace = WorkspaceModel(settings: settings, reader: reader)
        self.reader = reader
        self.settings = settings
        self.workspace = workspace
        let processRegistry = ChildProcessRegistry()
        self.sync = SyncModel(
            useCase: SyncUseCase(syncer: PythonSyncAdapter(tracker: processRegistry), credentials: credentials, reader: reader,
                                  installer: SyncScriptInstaller.bundled()),
            workspace: workspace, notifier: UserNotificationAdapter(),
            notificationPermission: { await UserNotificationScheduler().permission() })
        self.agents = AgentRunRegistry(runner: CLIAgentRunner(tracker: processRegistry), store: JSONAgentRunStore(),
                                       notifier: UserNotificationAdapter(), terminal: TerminalLauncher(), settings: settings)
        let agents = self.agents
        self.resources = ResourceMonitorModel(
            sampler: LibprocSampler(), processes: processRegistry, scanner: FileSystemDiskScanner(),
            runs: { [weak agents] in agents?.runs ?? [] }, workspaceRoot: { [weak settings] in
                settings?.workspaceURL ?? FileManager.default.homeDirectoryForCurrentUser
            })
        let commands = SlashCommandCatalog(
            store: JSONSlashCommandCatalogStore(),
            scanners: Dictionary(uniqueKeysWithValues: AgentProviderID.allCases.map {
                ($0, LocalSlashCommandScanner(layout: .layout(for: $0)) as SlashCommandScanning)
            }))
        self.commands = commands
        self.agents.onCommandsCatalog = { [weak commands] list, complete, provider in
            commands?.ingest(list, complete: complete, provider: provider)
        }
        self.agents.knownCommands = { [weak commands] provider, folder in
            commands?.providerCommandNames(in: folder, provider: provider) ?? []
        }
        let onboarding = OnboardingModel(settings: settings, auth: MoodleAuthChecker(), probe: DependencyProbe(),
                                         commands: CommandStreamer(), installer: SyncScriptInstaller.bundled())
        onboarding.reloadWorkspace = { [weak workspace] in await workspace?.reload() }
        let syncModel = self.sync
        onboarding.startSync = { syncModel.start(includeFiles: true) }
        self.onboarding = onboarding
        self.importFiles = ImportFilesUseCase(makeImporter: { FileSystemImporter(workspaceRoot: $0) })
        let reminders = ReminderModel(scheduler: UserNotificationScheduler(), settings: settings, workspace: workspace)
        self.reminders = reminders
        let contentIndex = ContentIndexModel(workspace: workspace)
        self.contentIndex = contentIndex
        // Full-text indexing writes under Application Support; never touch it under tests.
        let searchIndex = SearchIndexModel(workspace: workspace,
                                           store: env["XCTestConfigurationFilePath"] == nil ? try? SQLiteSearchIndex() : nil)
        self.searchIndex = searchIndex
        let review = self.review
        workspace.onReloaded = { [weak reminders, weak contentIndex, weak searchIndex, weak review, weak workspace] in
            if let workspace { review?.reload(courses: workspace.snapshot.courses, root: workspace.root) }
            reminders?.scheduleSoon()
            contentIndex?.workspaceChanged()
            searchIndex?.workspaceChanged()
        }
        settings.onRemindersChanged = { [weak reminders] in reminders?.scheduleSoon() }
        let underTest = env["XCTestConfigurationFilePath"] != nil
        func store<V: Codable & Sendable>(_ name: String) -> any StateStoring<V> {
            underTest ? MemoryStateStore<V>() : JSONStateStore<V>(name: name)
        }
        let notifier = UserNotificationAdapter()
        self.changes = ChangeTrackingModel(store: store("activity-changes.json"), notifier: notifier, notificationsEnabled: {
            let permission = await UserNotificationScheduler().permission()
            return GradeChangeNotification.isEnabled(preference: settings.changeNotificationsPreference, permission: permission)
        })
        self.focus = FocusTimerModel(store: store("focus-log.json"), notifier: notifier, settings: { settings.focusSettings })
        self.weekly = WeeklySummaryModel(store: store("weekly-summary.json"), runner: CLIAgentRunner(tracker: processRegistry),
                                         directory: WeeklySummaryModel.defaultDirectory, notifier: notifier)
        self.autopilot = AutopilotModel(store: store("autopilot.json"))
        self.teleprompter = TeleprompterModel(transcriber: AppleSpeechTranscriber(), presenter: nil)
        notchPanel.attach(model: teleprompter)
        teleprompter.attach(presenter: notchPanel)
        wireTracking()
        if !underTest { wireWidget() }
        wirePalette()
        if env["XCTestConfigurationFilePath"] == nil {
            notificationRouter.onOpenActivity = { [weak self] id in self?.reveal(activityID: id) }
            UNUserNotificationCenter.current().delegate = notificationRouter
        }
    }
}

/// Credential store used when the Keychain must not be touched; holds nothing.
struct EmptyCredentialStore: CredentialStoring {
    func load() -> SAIACredentials? { nil }
    func save(_ credentials: SAIACredentials) throws {}
    func delete() throws {}
}
