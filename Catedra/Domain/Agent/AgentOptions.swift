import Foundation

/// Provider-neutral permission levels, mapped to each CLI's own flags by its `AgentProvider`.
enum AgentPermissionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case readOnly, acceptEdits, automatic, unrestricted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .readOnly: "Solo lectura"
        case .acceptEdits: "Aceptar ediciones"
        case .automatic: "Automático"
        case .unrestricted: "Sin restricciones"
        }
    }

    func detail(for provider: AgentProviderID) -> String {
        switch self {
        case .readOnly: "Modo de planificación: el agente analiza y propone, pero no modifica archivos."
        case .acceptEdits:
            provider == .opencode
                ? "Permisos predeterminados de OpenCode; las acciones que requieren aprobación se rechazan."
                : "Edita archivos sin preguntar; otras acciones (p. ej. comandos) se deniegan."
        case .automatic: "El agente decide qué acciones permitir con un clasificador de seguridad."
        case .unrestricted: "Permite todas las acciones sin ninguna comprobación. Úselo con cuidado."
        }
    }

    /// Reads values stored by earlier versions (`AgentPermissionMode` raw values) as well as current ones.
    init?(storedValue: String) {
        switch storedValue {
        case "acceptEdits": self = .acceptEdits
        case "auto": self = .automatic
        case "bypassPermissions": self = .unrestricted
        case "plan": self = .readOnly
        default:
            guard let level = AgentPermissionLevel(rawValue: storedValue) else { return nil }
            self = level
        }
    }
}

/// A selectable model. `id` is the CLI value; nil means "use the CLI default" (no flag).
struct AgentModelOption: Identifiable, Hashable, Codable, Sendable {
    let id: String?
    let label: String

    var key: String { id ?? "" }

    static let cliDefault = AgentModelOption(id: nil, label: "Predeterminado")

    static let claudeModels: [AgentModelOption] = [
        .cliDefault,
        AgentModelOption(id: "opus", label: "Opus"),
        AgentModelOption(id: "sonnet", label: "Sonnet"),
        AgentModelOption(id: "haiku", label: "Haiku"),
    ]
}

struct AgentOptions: Equatable, Sendable {
    /// CLI model value; nil keeps the CLI default.
    var model: String? = nil
    var permission: AgentPermissionLevel = .acceptEdits
}

/// Everything the runner needs to launch one headless turn.
struct AgentRequest: Sendable {
    let runID: UUID
    let provider: AgentProviderID
    let executablePath: String
    let cwd: URL
    let prompt: String
    let resumeSessionId: String?
    let options: AgentOptions
    /// Names of the provider's custom commands (OpenCode runs a leading `/name` with `--command`).
    let knownCommands: Set<String>

    init(runID: UUID, provider: AgentProviderID = .claude, executablePath: String, cwd: URL, prompt: String,
         resumeSessionId: String?, options: AgentOptions, knownCommands: Set<String> = []) {
        self.runID = runID
        self.provider = provider
        self.executablePath = executablePath
        self.cwd = cwd
        self.prompt = prompt
        self.resumeSessionId = resumeSessionId
        self.options = options
        self.knownCommands = knownCommands
    }
}
