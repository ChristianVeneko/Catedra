import Foundation

/// Opens Terminal.app in a folder, optionally resuming a Claude session, through a temporary `.command` file.
struct TerminalLauncher: TerminalOpening {
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func script(folder: URL, executablePath: String, sessionId: String?) -> String {
        var command = shellQuote(executablePath)
        if let sessionId, !sessionId.isEmpty { command += " --resume \(shellQuote(sessionId))" }
        return "#!/bin/zsh\ncd \(shellQuote(folder.path)) && \(command)\n"
    }

    func openClaude(in folder: URL, executablePath: String, sessionId: String?) throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("catedra-claude-\(UUID().uuidString).command")
        try Self.script(folder: folder, executablePath: executablePath, sessionId: sessionId)
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", file.path]
        try process.run()
    }
}
