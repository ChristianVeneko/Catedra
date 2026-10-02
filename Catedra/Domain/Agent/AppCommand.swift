import Foundation

/// Slash commands handled by Cátedra itself; they are never sent to Claude.
enum AppCommand: Equatable, Sendable {
    case resume
    case newConversation
    case setModel(AgentModel)
    case setPermissionMode(AgentPermissionMode)
    case recipes
    case terminal
    case files
    /// A recognized app command with a missing or wrong argument; the message is shown to the user.
    case invalid(String)

    /// Entries for the popup's "Cátedra" section.
    static let definitions: [SlashCommand] = [
        SlashCommand(name: "resume", description: "Retomar una conversación anterior", argumentHint: nil, aliases: [], kind: .app),
        SlashCommand(name: "new", description: "Empezar una conversación nueva en esta carpeta", argumentHint: nil, aliases: ["clear"], kind: .app),
        SlashCommand(name: "model", description: "Elegir el modelo de esta conversación", argumentHint: "<opus|sonnet|haiku|predeterminado>", aliases: [], kind: .app),
        SlashCommand(name: "permisos", description: "Elegir el modo de permisos", argumentHint: "<aceptar|auto|sin-restricciones>", aliases: [], kind: .app),
        SlashCommand(name: "recetas", description: "Mostrar la galería de recetas", argumentHint: nil, aliases: [], kind: .app),
        SlashCommand(name: "terminal", description: "Abrir esta conversación en Terminal", argumentHint: nil, aliases: [], kind: .app),
        SlashCommand(name: "archivos", description: "Ver los archivos generados", argumentHint: nil, aliases: [], kind: .app),
    ]

    /// Names whose command needs an argument before it can run, so accepting it from the popup only inserts the text.
    static func requiresArgument(_ name: String) -> Bool {
        definitions.first { $0.name == name }?.argumentHint != nil
    }

    /// Parses a whole draft. Returns nil when it is not an app command (it then goes to Claude as-is).
    static func parse(_ text: String) -> AppCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.dropFirst().split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let head = parts.first else { return nil }
        let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch head.lowercased() {
        case "resume": return .resume
        case "new", "clear": return .newConversation
        case "recetas": return .recipes
        case "terminal": return .terminal
        case "archivos": return .files
        case "model":
            let options = "Use: /model opus, sonnet, haiku o predeterminado."
            guard !argument.isEmpty else { return .invalid(options) }
            guard let model = model(from: argument) else { return .invalid("Modelo desconocido «\(argument)». \(options)") }
            return .setModel(model)
        case "permisos":
            let options = "Use: /permisos aceptar, auto o sin-restricciones."
            guard !argument.isEmpty else { return .invalid(options) }
            guard let mode = permissionMode(from: argument) else { return .invalid("Modo desconocido «\(argument)». \(options)") }
            return .setPermissionMode(mode)
        default: return nil
        }
    }

    private static func model(from text: String) -> AgentModel? {
        switch text.lowercased() {
        case "opus": .opus
        case "sonnet": .sonnet
        case "haiku": .haiku
        case "predeterminado", "default": .default
        default: nil
        }
    }

    private static func permissionMode(from text: String) -> AgentPermissionMode? {
        switch text.lowercased() {
        case "aceptar", "acceptedits": .acceptEdits
        case "auto", "automatico", "automático": .auto
        case "sin-restricciones", "sinrestricciones", "bypasspermissions", "bypass": .bypassPermissions
        default: nil
        }
    }
}
