import Foundation

enum AgentModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case `default`, opus, sonnet, haiku

    var id: String { rawValue }

    /// Value for `--model`; nil keeps the CLI default.
    var cliAlias: String? { self == .default ? nil : rawValue }

    var label: String {
        switch self {
        case .default: "Predeterminado"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }
}

enum AgentPermissionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case acceptEdits, auto, bypassPermissions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .acceptEdits: "Aceptar ediciones"
        case .auto: "Automático"
        case .bypassPermissions: "Sin restricciones"
        }
    }

    var detail: String {
        switch self {
        case .acceptEdits: "Edita archivos sin preguntar; otras acciones (p. ej. comandos) se deniegan."
        case .auto: "El agente decide qué acciones permitir con un clasificador de seguridad."
        case .bypassPermissions: "Permite todas las acciones sin ninguna comprobación. Úselo con cuidado."
        }
    }
}

struct AgentOptions: Equatable, Sendable {
    var model: AgentModel = .default
    var permissionMode: AgentPermissionMode = .acceptEdits
}

/// Everything the runner needs to launch one headless turn.
struct AgentRequest: Sendable {
    let runID: UUID
    let executablePath: String
    let cwd: URL
    let prompt: String
    let resumeSessionId: String?
    let options: AgentOptions
}
