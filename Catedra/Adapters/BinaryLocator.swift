import Foundation

/// Finds the `claude` binary. A GUI app does not inherit the shell PATH, so well-known locations are checked
/// first and a login shell is the last resort. File-system and shell access are injectable for tests.
struct ClaudeLocator: Sendable {
    var home: String = NSHomeDirectory()
    var isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    var shellLookup: @Sendable () -> String? = { ClaudeLocator.loginShellLookup() }

    var candidates: [String] {
        ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    }

    /// `override` (from Settings) wins when it points to an executable file.
    func locate(override: String? = nil) -> String? {
        if let override, !override.isEmpty, isExecutable(override) { return override }
        if let found = candidates.first(where: isExecutable) { return found }
        if let path = shellLookup(), !path.isEmpty, isExecutable(path) { return path }
        return nil
    }

    static func loginShellLookup() -> String? {
        let output = LoginShellEnvironment.runShell("command -v claude")
        return output?.split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
    }
}
