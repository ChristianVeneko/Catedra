import Foundation

/// Finds a provider's executable. A GUI app does not inherit the shell PATH, so well-known locations are checked
/// first and a login shell is the last resort. File-system and shell access are injectable for tests.
struct BinaryLocator: Sendable {
    var provider: AgentProviderID
    var home: String = NSHomeDirectory()
    var isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    /// Overrides the login-shell lookup (tests); nil runs `command -v <binary>` in `zsh -lc`.
    var shellLookup: (@Sendable () -> String?)?

    init(provider: AgentProviderID, home: String = NSHomeDirectory(),
         isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
         shellLookup: (@Sendable () -> String?)? = nil) {
        self.provider = provider
        self.home = home
        self.isExecutable = isExecutable
        self.shellLookup = shellLookup
    }

    /// Directories checked in order, before the login shell.
    var directories: [String] {
        switch provider {
        case .claude: ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        case .antigravity: ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        case .opencode: ["\(home)/.bun/bin", "\(home)/.opencode/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
        }
    }

    var candidates: [String] { directories.map { "\($0)/\(provider.binaryName)" } }

    /// `override` (from Settings) wins when it points to an executable file.
    func locate(override: String? = nil) -> String? {
        if let override, !override.isEmpty, isExecutable(override) { return override }
        if let found = candidates.first(where: isExecutable) { return found }
        let lookup = shellLookup?() ?? Self.loginShellLookup(binary: provider.binaryName)
        if let lookup, !lookup.isEmpty, isExecutable(lookup) { return lookup }
        return nil
    }

    static func loginShellLookup(binary: String) -> String? {
        let output = LoginShellEnvironment.runShell("command -v \(binary)")
        return output?.split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
    }
}
