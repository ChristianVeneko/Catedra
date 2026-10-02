import Foundation
import Observation

/// User-configurable settings (non-secret values in UserDefaults) plus Keychain-backed credentials.
@Observable @MainActor
final class SettingsModel {
    static let defaultWorkspacePath = "/Users/christianmendoza/Desktop/UFT/7th semestre"

    var workspacePath: String { didSet { defaults.set(workspacePath, forKey: Keys.workspace) } }
    var pythonPath: String { didSet { defaults.set(pythonPath, forKey: Keys.python) } }
    var username: String
    var password: String = ""
    private(set) var hasStoredCredentials: Bool
    var statusMessage: String?
    var pythonStatus: String?

    private let defaults: UserDefaults
    private let store: CredentialStoring
    private enum Keys { static let workspace = "workspacePath"; static let python = "pythonPath" }

    init(store: CredentialStoring, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        self.workspacePath = defaults.string(forKey: Keys.workspace) ?? Self.defaultWorkspacePath
        self.pythonPath = defaults.string(forKey: Keys.python) ?? ""
        let creds = store.load()
        self.username = creds?.username ?? ""
        self.hasStoredCredentials = creds != nil
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
}
