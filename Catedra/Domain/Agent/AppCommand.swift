import Foundation

/// Slash commands handled by Cátedra itself; they are never sent to the agent.
enum AppCommand: Equatable, Sendable {
    case resume
    case newConversation
    /// CLI model value; nil restores the provider default.
    case setModel(String?)
    case setPermission(AgentPermissionLevel)
    case recipes
    case terminal
    case files
    /// A recognized app command with a missing or wrong argument; the message is shown to the user.
    case invalid(String)

    /// Entries for the popup's "Cátedra" section (Claude flavour; see `definitions(for:)`).
    static let definitions: [SlashCommand] = definitions(for: .claude)

    static func definitions(for provider: AgentProviderID) -> [SlashCommand] {
        let modelHint: String = switch provider {
        case .claude: "<opus|sonnet|haiku|predeterminado>"
        case .antigravity: "<id-del-modelo|predeterminado>"
        case .opencode: "<proveedor/modelo|predeterminado>"
        }
        let permissionHint = "<" + provider.supportedPermissions.map(\.commandWord).joined(separator: "|") + ">"
        return [
            SlashCommand(name: "resume", description: "Retomar una conversación anterior", argumentHint: nil, aliases: [], kind: .app),
            SlashCommand(name: "new", description: "Empezar una conversación nueva en esta carpeta", argumentHint: nil, aliases: ["clear"], kind: .app),
            SlashCommand(name: "model", description: "Elegir el modelo de esta conversación", argumentHint: modelHint, aliases: [], kind: .app),
            SlashCommand(name: "permisos", description: "Elegir el modo de permisos", argumentHint: permissionHint, aliases: [], kind: .app),
            SlashCommand(name: "recetas", description: "Mostrar la galería de recetas", argumentHint: nil, aliases: [], kind: .app),
            SlashCommand(name: "terminal", description: "Abrir esta conversación en Terminal", argumentHint: nil, aliases: [], kind: .app),
            SlashCommand(name: "archivos", description: "Ver los archivos generados", argumentHint: nil, aliases: [], kind: .app),
        ]
    }

    /// Names whose command needs an argument before it can run, so accepting it from the popup only inserts the text.
    static func requiresArgument(_ name: String) -> Bool {
        definitions.first { $0.name == name }?.argumentHint != nil
    }

    /// Parses a whole draft. Returns nil when it is not an app command (it then goes to the agent as-is).
    /// `models` are the provider's known models (used to validate `/model`).
    static func parse(_ text: String, provider: AgentProviderID = .claude, models: [AgentModelOption]? = nil) -> AppCommand? {
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
        case "model": return parseModel(argument, provider: provider, models: models)
        case "permisos": return parsePermission(argument, provider: provider)
        default: return nil
        }
    }

    // MARK: - Arguments

    private static func parseModel(_ argument: String, provider: AgentProviderID, models: [AgentModelOption]?) -> AppCommand {
        let hint = definitions(for: provider).first { $0.name == "model" }?.argumentHint ?? ""
        let options = "Use: /model \(hint.dropFirst().dropLast().replacingOccurrences(of: "|", with: ", "))."
        guard !argument.isEmpty else { return .invalid(options) }
        let lower = argument.lowercased()
        if lower == "predeterminado" || lower == "default" { return .setModel(nil) }
        let known = (models ?? knownModels(for: provider)).filter { $0.id != nil }
        if let match = known.first(where: { $0.id?.lowercased() == lower || $0.label.lowercased() == lower }) { return .setModel(match.id) }
        switch provider.modelSource {
        case .fixed: return .invalid("Modelo desconocido «\(argument)». \(options)")
        case .listed(let allowsCustom):
            if allowsCustom || known.isEmpty { return .setModel(argument) }
            return .invalid("Modelo desconocido «\(argument)». Elija uno del selector de modelos.")
        }
    }

    private static func knownModels(for provider: AgentProviderID) -> [AgentModelOption] {
        if case .fixed(let list) = provider.modelSource { return list }
        return []
    }

    private static func parsePermission(_ argument: String, provider: AgentProviderID) -> AppCommand {
        let options = "Use: /permisos " + provider.supportedPermissions.map(\.commandWord).joined(separator: ", ") + "."
        guard !argument.isEmpty else { return .invalid(options) }
        guard let level = AgentPermissionLevel(commandWord: argument) else { return .invalid("Modo desconocido «\(argument)». \(options)") }
        guard provider.supportedPermissions.contains(level) else {
            return .invalid("\(provider.displayName) no admite el modo «\(level.label)». \(options)")
        }
        return .setPermission(level)
    }
}

extension AgentPermissionLevel {
    /// Word shown in hints and accepted by `/permisos`.
    var commandWord: String {
        switch self {
        case .readOnly: "solo-lectura"
        case .acceptEdits: "aceptar"
        case .automatic: "auto"
        case .unrestricted: "sin-restricciones"
        }
    }

    init?(commandWord: String) {
        switch commandWord.lowercased() {
        case "solo-lectura", "sololectura", "lectura", "plan", "readonly": self = .readOnly
        case "aceptar", "acceptedits", "aceptar-ediciones": self = .acceptEdits
        case "auto", "automatico", "automático": self = .automatic
        case "sin-restricciones", "sinrestricciones", "bypasspermissions", "bypass", "yolo": self = .unrestricted
        default: return nil
        }
    }
}
