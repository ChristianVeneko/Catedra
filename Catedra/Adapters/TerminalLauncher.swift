import Foundation

/// Opens Terminal.app in a folder, optionally resuming an agent session, through a temporary `.command` file.
struct TerminalLauncher: TerminalOpening {
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func script(folder: URL, command: [String]) -> String {
        "#!/bin/zsh\ncd \(shellQuote(folder.path)) && \(command.map(shellQuote).joined(separator: " "))\n"
    }

    func open(in folder: URL, command: [String]) throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("catedra-agent-\(UUID().uuidString).command")
        try Self.script(folder: folder, command: command)
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", file.path]
        try process.run()
    }
}
