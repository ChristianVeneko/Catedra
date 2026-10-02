import Foundation

/// Runs small, bounded commands against a provider binary (`--version`, `models`) for the Settings screen.
struct AgentBinaryProbe: Sendable {
    var environment: @Sendable () -> [String: String] = { LoginShellEnvironment.childEnvironment() }

    /// Blocking: call off the main actor.
    func version(of executablePath: String, timeout: TimeInterval = 8) -> String? {
        run(executablePath, ["--version"], timeout: timeout).flatMap(VersionParser.parse)
    }

    /// Blocking: call off the main actor. Empty for providers without a model-list command.
    func models(for provider: AgentProviderID, executablePath: String, timeout: TimeInterval = 40) -> [AgentModelOption] {
        guard let arguments = provider.modelListArguments,
              let output = run(executablePath, arguments, timeout: timeout) else { return [] }
        return ModelListParser.parse(output, for: provider)
    }

    private func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var env = environment()
        env["PATH"] = LoginShellEnvironment.prepending(URL(fileURLWithPath: path).deletingLastPathComponent().path, to: env["PATH"])
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
