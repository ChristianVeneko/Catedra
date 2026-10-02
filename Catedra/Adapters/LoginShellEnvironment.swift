import Foundation

/// PATH of the user's login shell (cached), so tools the agent launches (python3, node, …) are found even
/// though a GUI app starts with a minimal environment.
enum LoginShellEnvironment {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedPath: String?

    static func fallbackDirectories(home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    /// Merges the login shell PATH, the current PATH and sane fallbacks, preserving order and dropping duplicates.
    static func mergedPath(shellPath: String?, currentPath: String?, home: String = NSHomeDirectory()) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        let sources: [String?] = [shellPath, currentPath, fallbackDirectories(home: home).joined(separator: ":")]
        for source in sources {
            for dir in (source ?? "").split(separator: ":").map(String.init) where !dir.isEmpty && seen.insert(dir).inserted {
                parts.append(dir)
            }
        }
        return parts.joined(separator: ":")
    }

    /// `path` with `directory` first (used so a script's sibling `node`/`bun` is found); no duplicates.
    static func prepending(_ directory: String, to path: String?) -> String {
        var parts = (path ?? "").split(separator: ":").map(String.init)
        guard !parts.contains(directory) else { return parts.joined(separator: ":") }
        parts.insert(directory, at: 0)
        return parts.joined(separator: ":")
    }

    /// Environment for the agent process. Blocking (spawns a login shell once); call off the main actor.
    static func childEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["PATH"] = mergedPath(shellPath: loginPath(), currentPath: base["PATH"])
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        // Never let a parent Claude Code session leak its markers into the child.
        for key in env.keys where key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") { env[key] = nil }
        return env
    }

    static func loginPath() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cachedPath { return cachedPath }
        let value = runShell("echo $PATH")?.split(separator: "\n").map(String.init).last { $0.contains("/") }
        cachedPath = value
        return value
    }

    /// Runs `zsh -lc <command>` and returns stdout, or nil on failure.
    static func runShell(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
