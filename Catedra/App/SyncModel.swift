import Foundation
import Observation

@Observable @MainActor
final class SyncModel {
    enum State: Equatable { case idle, running, finished(SyncOutcome) }

    /// Non-modal message shown after a background sync.
    enum Banner: Equatable {
        case summary(String)
        case failure(String, needsSettings: Bool)
    }

    private(set) var state: State = .idle
    private(set) var log: [SyncLogLine] = []
    private(set) var currentCourse: String?
    private(set) var lastIncludeFiles = true
    private(set) var isBackground = false
    private(set) var banner: Banner?
    var isPresented = false

    private let useCase: SyncUseCase
    private let workspace: WorkspaceModel
    private let notifier: AgentNotifying?
    private let notificationPermission: @Sendable () async -> NotificationPermission
    private var task: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private(set) var launchSyncAttempted = false
    /// Called after every successful sync, once the workspace has been reloaded.
    var onSyncSucceeded: (@MainActor (ActivityDiff) async -> Void)?

    init(useCase: SyncUseCase, workspace: WorkspaceModel, notifier: AgentNotifying? = nil,
         notificationPermission: @escaping @Sendable () async -> NotificationPermission = { .notDetermined }) {
        self.notificationPermission = notificationPermission
        self.useCase = useCase
        self.workspace = workspace
        self.notifier = notifier
    }

    var isRunning: Bool { state == .running }

    /// A manual run opens the sheet; a background run stays silent. Starting while a run is active just shows its log.
    func start(includeFiles: Bool, background: Bool = false) {
        guard !isRunning else { if !background { isPresented = true }; return }
        lastIncludeFiles = includeFiles
        isBackground = background
        log = []
        currentCourse = nil
        dismissBanner()
        state = .running
        isPresented = !background
        let settings = workspace.settings
        let stream = useCase.execute(root: settings.workspaceURL, pythonPath: settings.pythonPath, includeFiles: includeFiles,
                                     lowPriority: background)
        task = Task { [weak self] in
            for await progress in stream {
                guard let self else { return }
                switch progress {
                case .log(let line):
                    self.log.append(line)
                    if case .course(let name) = line.event { self.currentCourse = name }
                case .finished(let outcome):
                    self.state = .finished(outcome)
                }
            }
            if let self {
                if self.state == .running { self.state = .finished(.failed(exitCode: -1)) }
                await self.workspace.reload()
                await self.completed()
            }
        }
    }

    /// Applies `LaunchSyncPolicy` once per process; returns the decision for diagnostics.
    @discardableResult
    func startOnLaunchIfNeeded(onboardingCompleted: Bool, disabledByEnvironment: Bool, now: Date = .now) -> LaunchSyncPolicy.Decision {
        let settings = workspace.settings
        guard !launchSyncAttempted else { return .skip(.syncInProgress) }
        launchSyncAttempted = true
        let decision = LaunchSyncPolicy.decide(
            mode: settings.launchSyncMode, onboardingCompleted: onboardingCompleted,
            hasCredentials: settings.hasStoredCredentials,
            hasPython: !settings.pythonPath.isEmpty && FileManager.default.isExecutableFile(atPath: settings.pythonPath),
            lastSuccess: settings.lastSuccessfulSync, now: now, minIntervalMinutes: settings.launchSyncMinIntervalMinutes,
            isSyncRunning: isRunning, disabledByEnvironment: disabledByEnvironment)
        if case .start(let includeFiles) = decision { start(includeFiles: includeFiles, background: true) }
        return decision
    }

    func cancel() {
        task?.cancel()
        if isRunning { state = .finished(.failed(exitCode: -15)) }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    private func completed() async {
        guard case .finished(let outcome) = state else { return }
        if case .success(let diff) = outcome {
            workspace.settings.recordSuccessfulSync()
            await notifyGradeChanges(diff.gradeChanges)
            await onSyncSucceeded?(diff)
            guard isBackground else { return }
            let text = SyncSummary.text(for: diff)
            show(.summary(text), autoDismiss: true)
            if SyncSummary.isNotable(diff) {
                await notifier?.notifyFinished(title: "Cátedra: actividades actualizadas", body: text)
            }
        } else if isBackground, let failure = SyncSummary.failure(for: outcome) {
            show(.failure(failure.text, needsSettings: failure.needsSettings), autoDismiss: false)
        }
    }

    /// Own toggle, independent of deadline reminders; the notifier stays silent while the app is frontmost.
    private func notifyGradeChanges(_ changes: [GradeChange]) async {
        guard let content = GradeChangeNotification.content(for: changes) else { return }
        let permission = await notificationPermission()
        guard GradeChangeNotification.isEnabled(preference: workspace.settings.gradeNotificationsPreference, permission: permission) else { return }
        await notifier?.notifyFinished(title: content.title, body: content.body)
    }

    private func show(_ newBanner: Banner, autoDismiss: Bool) {
        bannerTask?.cancel()
        banner = newBanner
        guard autoDismiss else { return }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}
