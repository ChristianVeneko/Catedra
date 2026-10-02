import Foundation
import Observation

/// User-configurable settings (non-secret values in UserDefaults) plus Keychain-backed credentials.
@Observable @MainActor
final class SettingsModel {
    static let defaultWorkspacePath = "/Users/christianmendoza/Desktop/UFT/7th semestre"

    var workspacePath: String { didSet { defaults.set(workspacePath, forKey: Keys.workspace) } }
    var pythonPath: String { didSet { defaults.set(pythonPath, forKey: Keys.python) } }
    /// Provider used for new conversations.
    var agentProvider: AgentProviderID { didSet { defaults.set(agentProvider.rawValue, forKey: Keys.provider) } }
    /// Executable overrides; an empty value means "auto-detect".
    var binaryPaths: [AgentProviderID: String] { didSet { persist(binaryPaths, prefix: Keys.path) } }
    /// Default model per provider ("" keeps the CLI default).
    var defaultModels: [AgentProviderID: String] { didSet { persist(defaultModels, prefix: Keys.model) } }
    var defaultPermissions: [AgentProviderID: AgentPermissionLevel] {
        didSet { persist(defaultPermissions.mapValues(\.rawValue), prefix: Keys.permission) }
    }
    /// Menu bar extra visibility and whether it shows the next deadline countdown.
    var menuBarVisible: Bool { didSet { defaults.set(menuBarVisible, forKey: Keys.menuBar) } }
    var menuBarShowsCountdown: Bool { didSet { defaults.set(menuBarShowsCountdown, forKey: Keys.menuBarCountdown) } }
    var reminders: ReminderPreferences {
        didSet {
            persistReminders()
            if reminders != oldValue { onRemindersChanged?() }
        }
    }
    var onRemindersChanged: (@MainActor () -> Void)?
    private(set) var statuses: [AgentProviderID: BinaryStatus] = [:]
    /// Models reported by `agy models` / `opencode models` (cached in UserDefaults).
    private(set) var modelLists: [AgentProviderID: [AgentModelOption]]
    private(set) var loadingModels: Set<AgentProviderID> = []
    var username: String
    var password: String = ""
    private(set) var hasStoredCredentials: Bool
    var statusMessage: String?
    var pythonStatus: String?

    private let defaults: UserDefaults
    private let store: CredentialStoring
    private enum Keys {
        static let workspace = "workspacePath", python = "pythonPath"
        static let menuBar = "menuBarVisible", menuBarCountdown = "menuBarShowsCountdown"
        static let remindersEnabled = "reminders.enabled", reminder48 = "reminders.48h", reminder24 = "reminders.24h",
                   reminder3 = "reminders.3h", reminderCustom = "reminders.custom", reminderCustomHours = "reminders.customHours"
        static let provider = "agentProvider", path = "agentPath.", model = "agentModel.", permission = "agentPermission.", models = "agentModelList."
        // Keys written before multi-provider support (Claude only).
        static let legacyClaudePath = "claudePath", legacyModel = "agentModel", legacyMode = "agentPermissionMode"
    }

    init(store: CredentialStoring, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        self.workspacePath = defaults.string(forKey: Keys.workspace) ?? Self.defaultWorkspacePath
        self.pythonPath = defaults.string(forKey: Keys.python) ?? ""
        self.menuBarVisible = defaults.object(forKey: Keys.menuBar) as? Bool ?? true
        self.menuBarShowsCountdown = defaults.object(forKey: Keys.menuBarCountdown) as? Bool ?? true
        var reminders = ReminderPreferences()
        reminders.enabled = defaults.object(forKey: Keys.remindersEnabled) as? Bool ?? false
        reminders.at48h = defaults.object(forKey: Keys.reminder48) as? Bool ?? true
        reminders.at24h = defaults.object(forKey: Keys.reminder24) as? Bool ?? true
        reminders.at3h = defaults.object(forKey: Keys.reminder3) as? Bool ?? true
        reminders.customEnabled = defaults.object(forKey: Keys.reminderCustom) as? Bool ?? false
        reminders.customHours = max(1, defaults.object(forKey: Keys.reminderCustomHours) as? Int ?? 12)
        self.reminders = reminders
        self.agentProvider = defaults.string(forKey: Keys.provider).flatMap(AgentProviderID.init(rawValue:)) ?? .claude
        var paths: [AgentProviderID: String] = [:], models: [AgentProviderID: String] = [:]
        var permissions: [AgentProviderID: AgentPermissionLevel] = [:]
        var lists: [AgentProviderID: [AgentModelOption]] = [:]
        for provider in AgentProviderID.allCases {
            paths[provider] = defaults.string(forKey: Keys.path + provider.rawValue) ?? ""
            models[provider] = defaults.string(forKey: Keys.model + provider.rawValue) ?? ""
            permissions[provider] = defaults.string(forKey: Keys.permission + provider.rawValue).flatMap(AgentPermissionLevel.init(storedValue:)) ?? .acceptEdits
            if let data = defaults.data(forKey: Keys.models + provider.rawValue),
               let list = try? JSONDecoder().decode([AgentModelOption].self, from: data) { lists[provider] = list }
        }
        // Carry Claude settings over from earlier versions.
        if paths[.claude]?.isEmpty == true { paths[.claude] = defaults.string(forKey: Keys.legacyClaudePath) ?? "" }
        if defaults.string(forKey: Keys.model + "claude") == nil, let old = defaults.string(forKey: Keys.legacyModel), old != "default" { models[.claude] = old }
        if defaults.string(forKey: Keys.permission + "claude") == nil,
           let old = defaults.string(forKey: Keys.legacyMode).flatMap(AgentPermissionLevel.init(storedValue:)) { permissions[.claude] = old }
        self.binaryPaths = paths
        self.defaultModels = models
        self.defaultPermissions = permissions
        self.modelLists = lists
        let creds = store.load()
        self.username = creds?.username ?? ""
        self.hasStoredCredentials = creds != nil
    }

    private func persistReminders() {
        defaults.set(reminders.enabled, forKey: Keys.remindersEnabled)
        defaults.set(reminders.at48h, forKey: Keys.reminder48)
        defaults.set(reminders.at24h, forKey: Keys.reminder24)
        defaults.set(reminders.at3h, forKey: Keys.reminder3)
        defaults.set(reminders.customEnabled, forKey: Keys.reminderCustom)
        defaults.set(reminders.customHours, forKey: Keys.reminderCustomHours)
    }

    var workspaceURL: URL { URL(fileURLWithPath: workspacePath, isDirectory: true) }

    func saveCredentials() {
        guard !username.isEmpty, !password.isEmpty else {
            statusMessage = "Ingrese usuario y contraseña."; return
        }
        do {
            try store.save(SAIACredentials(username: username, password: password))
            password = ""
            hasStoredCredentials = true
            statusMessage = "Credenciales guardadas en el llavero."
        } catch { statusMessage = error.localizedDescription }
    }

    func deleteCredentials() {
        do {
            try store.delete()
            username = ""; password = ""; hasStoredCredentials = false
            statusMessage = "Credenciales eliminadas."
        } catch { statusMessage = error.localizedDescription }
    }

    func detectPython() async {
        pythonStatus = "Buscando…"
        if let path = await PythonLocator.detect() {
            pythonPath = path
            pythonStatus = "Detectado: \(path)"
        } else {
            pythonStatus = "No se encontró un Python con el módulo «requests». Instálelo con: python3 -m pip install requests"
        }
    }

    func validatePython() async {
        guard !pythonPath.isEmpty else { pythonStatus = nil; return }
        pythonStatus = await PythonLocator.hasRequests(pythonPath)
            ? "Intérprete válido (módulo «requests» disponible)."
            : "El intérprete no existe o no tiene el módulo «requests»."
    }

    // MARK: - Agent providers

    enum BinaryStatus: Equatable {
        case checking
        case found(path: String, version: String?)
        case notInstalled
        case invalidOverride
    }

    private func persist<V>(_ values: [AgentProviderID: V], prefix: String) {
        for (provider, value) in values { defaults.set(value, forKey: prefix + provider.rawValue) }
    }

    /// Settings override when valid, otherwise auto-detected location.
    func resolvedPath(for provider: AgentProviderID, locator: BinaryLocator? = nil) -> String? {
        (locator ?? BinaryLocator(provider: provider)).locate(override: binaryPaths[provider])
    }

    /// Model and permission a new conversation starts with for `provider`.
    func defaultOptions(for provider: AgentProviderID) -> AgentOptions {
        let model = defaultModels[provider].flatMap { $0.isEmpty ? nil : $0 }
        return AgentOptions(model: model, permission: provider.normalized(defaultPermissions[provider] ?? .acceptEdits))
    }

    /// Models offered in pickers: the fixed list, or "Predeterminado" plus what the CLI reported.
    func modelOptions(for provider: AgentProviderID) -> [AgentModelOption] {
        switch provider.modelSource {
        case .fixed(let list): list
        case .listed: [.cliDefault] + (modelLists[provider] ?? [])
        }
    }

    /// Finds the binary, stores it as the path and refreshes the status line.
    func detect(_ provider: AgentProviderID) async {
        statuses[provider] = .checking
        let found = await Task.detached { BinaryLocator(provider: provider).locate() }.value
        if let found { binaryPaths[provider] = found }
        await refreshStatus(provider)
    }

    /// Re-evaluates the binary (override or auto-detected) and its version; loads the model list on first success.
    func refreshStatus(_ provider: AgentProviderID) async {
        let override = binaryPaths[provider] ?? ""
        let path = resolvedPath(for: provider)
        guard let path else {
            statuses[provider] = override.isEmpty ? .notInstalled : .invalidOverride
            return
        }
        statuses[provider] = .checking
        let version = await Task.detached { AgentBinaryProbe().version(of: path) }.value
        statuses[provider] = .found(path: path, version: version)
        if provider.modelListArguments != nil, modelLists[provider]?.isEmpty ?? true { await loadModels(for: provider) }
    }

    /// Runs `<bin> models` and caches the result.
    func loadModels(for provider: AgentProviderID) async {
        guard provider.modelListArguments != nil, let path = resolvedPath(for: provider), loadingModels.insert(provider).inserted else { return }
        let list = await Task.detached { AgentBinaryProbe().models(for: provider, executablePath: path) }.value
        loadingModels.remove(provider)
        guard !list.isEmpty else { return }
        modelLists[provider] = list
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Keys.models + provider.rawValue) }
    }
}
