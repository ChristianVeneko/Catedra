import Foundation

/// The agent CLIs Cátedra can drive. Raw values are persisted (settings, stored runs).
enum AgentProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, antigravity, opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .antigravity: "Antigravity"
        case .opencode: "OpenCode"
        }
    }

    /// Executable name looked up on disk and in the login shell.
    var binaryName: String {
        switch self {
        case .claude: "claude"
        case .antigravity: "agy"
        case .opencode: "opencode"
        }
    }

    /// Text shown (and copyable) in Settings when the binary is missing.
    var installHint: String {
        switch self {
        case .claude: "curl -fsSL https://claude.ai/install.sh | bash"
        case .antigravity: "Instala Antigravity desde antigravity.google"
        case .opencode: "curl -fsSL https://opencode.ai/install | bash"
        }
    }

    /// True when `installHint` is a shell command (copyable and runnable) rather than a pointer to a website.
    var installHintIsCommand: Bool { self != .antigravity }

    /// Title of the popup section that lists the provider's own skills / commands.
    var slashSectionTitle: String {
        switch self {
        case .claude: "Comandos de Claude Code"
        case .antigravity: "Skills / Comandos de Antigravity"
        case .opencode: "Skills / Comandos de OpenCode"
        }
    }

    /// Permission levels the provider can express in headless mode. Unsupported levels are hidden.
    var supportedPermissions: [AgentPermissionLevel] {
        switch self {
        case .claude: [.readOnly, .acceptEdits, .automatic, .unrestricted]
        case .antigravity, .opencode: [.readOnly, .acceptEdits, .unrestricted]
        }
    }

    /// `level` when supported, otherwise the safe default.
    func normalized(_ level: AgentPermissionLevel) -> AgentPermissionLevel {
        supportedPermissions.contains(level) ? level : .acceptEdits
    }

    /// Where the popup's provider commands come from.
    enum SlashCatalogSource: Sendable { case stream, localScan }
    var slashCatalogSource: SlashCatalogSource { self == .claude ? .stream : .localScan }

    var modelSource: ModelSource {
        switch self {
        case .claude: .fixed(AgentModelOption.claudeModels)
        case .antigravity: .listed(allowsCustom: false)
        case .opencode: .listed(allowsCustom: true)
        }
    }

    /// Subcommand (after the binary) that prints the available models; nil for providers with a fixed list.
    var modelListArguments: [String]? {
        switch self {
        case .claude: nil
        case .antigravity, .opencode: ["models"]
        }
    }

    /// Arguments of the interactive CLI that resume a session; empty when there is nothing to resume.
    func terminalResumeArguments(sessionId: String?) -> [String] {
        guard let sessionId, !sessionId.isEmpty else { return [] }
        switch self {
        case .claude: return ["--resume", sessionId]
        case .antigravity: return ["--conversation", sessionId]
        case .opencode: return ["--session", sessionId]
        }
    }

    var tosWarning: String? {
        self == .opencode
            ? "No inicies sesión en OpenCode con tu suscripción de Claude Pro/Max: Anthropic no lo permite. Usa otro proveedor o una clave de API."
            : nil
    }
}

enum ModelSource: Sendable, Equatable {
    case fixed([AgentModelOption])
    /// Loaded from the CLI (`<bin> models`); `allowsCustom` lets the user type any identifier.
    case listed(allowsCustom: Bool)
}
