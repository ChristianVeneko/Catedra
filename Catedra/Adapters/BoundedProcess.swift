import Foundation

/// Runs one short command with a hard timeout and returns its output. Blocking: call off the main actor.
enum BoundedProcess {
    struct Result: Sendable, Equatable {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
        var output: String { [stdout, stderr].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "" }
    }

    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval = 8) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timedOut = TimedOutFlag()
        let watchdog = DispatchWorkItem { if process.isRunning { timedOut.set(); process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Drain stderr concurrently so a chatty command cannot fill the pipe and stall.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errBox.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()
        return Result(status: process.terminationStatus, stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errBox.data, as: UTF8.self), timedOut: timedOut.value)
    }

    /// `command -v <name>` in a login shell, so Homebrew / user installs on the shell PATH are found.
    static func which(_ name: String, timeout: TimeInterval = 10) -> String? {
        guard let result = run("/bin/zsh", ["-lc", "command -v \(name)"], timeout: timeout), result.status == 0 else { return nil }
        return result.stdout.split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
    }

    private final class TimedOutFlag: @unchecked Sendable {
        private let lock = NSLock(); private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }
    private final class DataBox: @unchecked Sendable { var data = Data() }
}
