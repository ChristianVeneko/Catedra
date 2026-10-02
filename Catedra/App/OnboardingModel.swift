import Foundation
import Observation

/// State and actions of the first-run setup wizard. Nothing is written to settings, the Keychain or the workspace
/// until the user finishes the last step.
@Observable @MainActor
final class OnboardingModel {
    enum Step: Int, CaseIterable, Comparable {
        case welcome, folder, credentials, agent, dependencies, done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .welcome: "Bienvenida"
            case .folder: "Carpeta de datos"
            case .credentials: "Credenciales del SAIA"
            case .agent: "Agente"
            case .dependencies: "Dependencias"
            case .done: "Listo"
            }
        }
    }

    enum AuthState: Equatable { case idle, testing, finished(MoodleAuthResult) }

    enum Keys {
        static let completed = "onboardingCompleted"
        static let incomplete = "setupIncomplete"
        static let force = "CatedraForceOnboarding"
    }

    // Navigation
    private(set) var step: Step = .welcome

    // Folder
    var folderPath = ""
    private(set) var inspection: WorkspaceInspection?
    var createStarterFiles = true

    // Credentials
    var username = ""
    var password = ""
    private(set) var authState: AuthState = .idle

    // Agent
    var provider: AgentProviderID = .claude

    // Dependencies
    private(set) var observations: [DependencyID: DependencyObservation] = [:]
    private(set) var pythonPath = ""
    private(set) var isChecking = false
    private(set) var pipOutput: [String] = []
    private(set) var isInstallingRequests = false

    // Finish
    var syncNow = true
    private(set) var finishError: String?
    private(set) var isFinishing = false

    /// Warning shown in the main window while a required dependency is still missing after the wizard.
    private(set) var setupWarning: String?

    var reloadWorkspace: @MainActor () async -> Void = {}
    var startSync: @MainActor () -> Void = {}

    private let settings: SettingsModel
    private let auth: MoodleAuthChecking
    private let probe: DependencyProbing
    private let commands: CommandStreaming
    private let installer: SyncScriptInstalling?
    private let inspector: WorkspaceInspector
    private let starterWriter: StarterFilesWriter
    private let defaults: UserDefaults
    private let home: String
    private var checkTask: Task<Void, Never>?
    private var didAutoPresent = false
    private let forcedAtLaunch: Bool

    init(settings: SettingsModel, auth: MoodleAuthChecking, probe: DependencyProbing, commands: CommandStreaming,
         installer: SyncScriptInstalling?, inspector: WorkspaceInspector = WorkspaceInspector(),
         starterWriter: StarterFilesWriter = StarterFilesWriter(), defaults: UserDefaults = .standard,
         home: String = NSHomeDirectory()) {
        self.settings = settings; self.auth = auth; self.probe = probe; self.commands = commands
        self.installer = installer; self.inspector = inspector; self.starterWriter = starterWriter
        self.defaults = defaults; self.home = home
        self.forcedAtLaunch = defaults.bool(forKey: Keys.force)
    }

    // MARK: - Presentation

    var isCompleted: Bool { defaults.bool(forKey: Keys.completed) }

    /// True once per launch when the wizard should open by itself (first run, or `-CatedraForceOnboarding YES`).
    func consumeAutoPresent() -> Bool {
        guard !didAutoPresent else { return false }
        didAutoPresent = true
        return forcedAtLaunch || !isCompleted
    }

    /// Resets the wizard to its first step with the current settings and starts the dependency checks.
    func begin() {
        step = .welcome
        username = settings.username
        password = ""
        authState = .idle
        provider = settings.agentProvider
        pipOutput = []
        finishError = nil
        syncNow = true
        setFolder(Self.initialFolder(currentPath: settings.workspacePath, isExplicit: defaults.object(forKey: "workspacePath") != nil,
                                     inspector: inspector, home: home))
        recheck()
    }

    /// The folder the wizard starts with: the configured one when the user chose it or it already holds a synced
    /// workspace, otherwise `~/Documents/Cátedra`.
    static func initialFolder(currentPath: String, isExplicit: Bool, inspector: WorkspaceInspector, home: String) -> String {
        let current = inspector.inspect(URL(fileURLWithPath: currentPath, isDirectory: true))
        if isExplicit || current.existingActivityCount != nil { return currentPath }
        return "\(home)/Documents/Cátedra"
    }

    // MARK: - Navigation

    var canAdvance: Bool {
        switch step {
        case .folder: inspection?.isWritable == true
        default: true
        }
    }

    var isFirst: Bool { step == .welcome }
    var isLast: Bool { step == .done }

    func next() {
        guard canAdvance, let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func go(to target: Step) { if target <= step { step = target } }

    // MARK: - Folder

    func setFolder(_ path: String) {
        folderPath = path
        let result = inspector.inspect(URL(fileURLWithPath: path, isDirectory: true))
        inspection = result
        createStarterFiles = result.existingActivityCount == nil && !result.hasAgentInstructions
    }

    /// The starter instruction files are offered only for a new workspace that has none of its own.
    var offersStarterFiles: Bool {
        guard let inspection else { return false }
        return inspection.existingActivityCount == nil && !inspection.hasAgentInstructions
    }

    var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }

    // MARK: - Credentials

    var hasStoredCredentials: Bool { settings.hasStoredCredentials }
    var canTestConnection: Bool { !username.isEmpty && !password.isEmpty && authState != .testing }

    func testConnection() {
        guard canTestConnection else { return }
        authState = .testing
        let user = username, pass = password
        let checker = auth
        Task {
            let result = await checker.check(username: user, password: pass)
            authState = .finished(result)
        }
    }

    func credentialsChanged() { if authState != .testing { authState = .idle } }

    // MARK: - Dependencies

    var checks: [DependencyCheck] {
        DependencyPlan.specs(selectedAgent: provider).map { spec in
            guard let observation = observations[spec.id] else {
                return DependencyCheck(id: spec.id, name: spec.name, requirement: spec.requirement, status: .checking,
                                       installCommand: spec.installCommand, installIsCommand: spec.installIsCommand, note: spec.note)
            }
            return DependencyEvaluator.evaluate(spec, observation)
        }
    }

    var readiness: DependencyReadiness { DependencyEvaluator.readiness(checks) }

    func check(for provider: AgentProviderID) -> DependencyCheck? { checks.first { $0.id == .agent(provider) } }

    func recheck() {
        checkTask?.cancel()
        observations = [:]
        isChecking = true
        let probe = probe
        var context = DependencyProbeContext(pythonPath: Self.usable(settings.pythonPath), agentPaths: settings.binaryPaths)
        checkTask = Task { [weak self] in
            // Python first: the `requests` check runs against the interpreter that was chosen.
            let python = await probe.observe(.python, context: context)
            guard !Task.isCancelled, let self else { return }
            self.observations[.python] = python
            if case .found(let path?, _) = python { context.pythonPath = path; self.pythonPath = path }
            let ctx = context
            await withTaskGroup(of: (DependencyID, DependencyObservation).self) { group in
                let others: [DependencyID] = [.requests, .git, .node] + AgentProviderID.allCases.map { .agent($0) }
                for id in others { group.addTask { (id, await probe.observe(id, context: ctx)) } }
                for await (id, observation) in group where !Task.isCancelled { self.observations[id] = observation }
            }
            if !Task.isCancelled { self.isChecking = false }
        }
    }

    private static func usable(_ path: String) -> String {
        FileManager.default.isExecutableFile(atPath: path) ? path : ""
    }

    /// Runs `python -m pip install --user requests`, streaming the output, then checks again. Only on explicit request.
    func installRequests() {
        guard !isInstallingRequests, !pythonPath.isEmpty else { return }
        isInstallingRequests = true
        pipOutput = ["$ \(pythonPath) -m pip install --user requests"]
        let stream = commands.run(pythonPath, arguments: ["-m", "pip", "install", "--user", "requests"])
        Task {
            for await output in stream {
                switch output {
                case .line(let text, _): pipOutput.append(text)
                case .finished(let code): pipOutput.append(code == 0 ? "Instalación completada." : "La instalación terminó con errores (código \(code)).")
                }
            }
            isInstallingRequests = false
            recheck()
        }
    }

    // MARK: - Finish

    var summary: [(title: String, value: String)] {
        var rows = [("Carpeta de datos", folderPath), ("Agente", provider.displayName)]
        if let count = inspection?.existingActivityCount { rows.append(("Espacio existente", "\(count) actividades")) }
        let hasCredentials = !username.isEmpty && (!password.isEmpty || hasStoredCredentials)
        rows.append(("Cuenta de SAIA", hasCredentials ? username : "Sin configurar"))
        switch readiness {
        case .ready: rows.append(("Dependencias", "Todo listo"))
        case .checking: rows.append(("Dependencias", "Comprobando…"))
        case .blocked(let ids): rows.append(("Dependencias", "Faltan \(ids.count) obligatorias"))
        }
        return rows
    }

    var canSyncNow: Bool { readiness == .ready && ((!username.isEmpty && !password.isEmpty) || hasStoredCredentials) }

    func finish() async -> Bool {
        guard !isFinishing else { return false }
        isFinishing = true
        finishError = nil
        defer { isFinishing = false }
        do {
            let folder = folderURL
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if offersStarterFiles && createStarterFiles { _ = try starterWriter.write(into: folder) }
            _ = try installer?.install(workspace: folder)
        } catch {
            finishError = error.localizedDescription
            return false
        }
        settings.workspacePath = folderPath
        settings.agentProvider = provider
        if !pythonPath.isEmpty { settings.pythonPath = pythonPath }
        if !username.isEmpty, !password.isEmpty {
            settings.username = username
            settings.password = password
            settings.saveCredentials()
            if let message = settings.statusMessage, !settings.hasStoredCredentials { finishError = message; return false }
        }
        password = ""
        let blocked = readiness != .ready
        defaults.set(true, forKey: Keys.completed)
        defaults.set(blocked, forKey: Keys.incomplete)
        updateWarning()
        await reloadWorkspace()
        if syncNow, canSyncNow { startSync() }
        return true
    }

    // MARK: - Warning banner

    /// After launch: when the wizard was finished with missing requirements, check again and update the banner.
    func refreshWarningIfNeeded() async {
        guard isCompleted, defaults.bool(forKey: Keys.incomplete) else { return }
        provider = settings.agentProvider
        let probe = probe
        var context = DependencyProbeContext(pythonPath: Self.usable(settings.pythonPath), agentPaths: settings.binaryPaths)
        let python = await probe.observe(.python, context: context)
        observations[.python] = python
        if case .found(let path?, _) = python { context.pythonPath = path; pythonPath = path }
        observations[.requests] = await probe.observe(.requests, context: context)
        observations[.agent(provider)] = await probe.observe(.agent(provider), context: context)
        updateWarning()
        if setupWarning == nil { defaults.set(false, forKey: Keys.incomplete) }
    }

    private func updateWarning() {
        let blocking = checks.filter(\.blocksReadiness).map(\.name)
        setupWarning = blocking.isEmpty ? nil : "Falta configurar: \(blocking.joined(separator: ", ")). La sincronización o el agente pueden no funcionar."
    }
}
