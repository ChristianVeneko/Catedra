import Foundation

/// Runs the installed `_sistema/sync_moodle.py` (see `SyncScriptInstaller`) with `--root <workspace>` and streams its output. Credentials go only through the process environment.
struct PythonSyncAdapter: MoodleSyncing {
    var tracker: ChildProcessTracking?

    func run(_ configuration: SyncConfiguration) -> AsyncStream<SyncOutput> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: configuration.pythonPath)
            var args = ["sync_moodle.py", "--root", configuration.workspaceRoot.path]
            if !configuration.includeFiles { args.append("--no-files") }
            process.arguments = args
            if configuration.lowPriority { process.qualityOfService = .utility }
            process.currentDirectoryURL = configuration.workspaceRoot.appendingPathComponent("_sistema", isDirectory: true)

            var env = ProcessInfo.processInfo.environment
            env["MOODLE_USER"] = configuration.username
            env["MOODLE_PASS"] = configuration.password
            env["MOODLE_TOKEN"] = nil // never let an ambient token override the stored credentials
            env["PYTHONUNBUFFERED"] = "1"
            env["PYTHONIOENCODING"] = "utf-8"
            process.environment = env

            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice // an interactive prompt must hit EOF, never block

            let readers = [(out, false), (err, true)].map { pipe, isError in
                Task.detached {
                    do {
                        for try await line in pipe.fileHandleForReading.bytes.lines {
                            continuation.yield(.line(line, isError: isError))
                        }
                    } catch {}
                }
            }

            do { try process.run() } catch {
                continuation.yield(.line("No se pudo iniciar Python: \(error.localizedDescription)", isError: true))
                continuation.yield(.finished(exitCode: -1))
                continuation.finish()
                return
            }

            let tracker = self.tracker
            tracker?.didStart(.sync, pid: process.processIdentifier)
            Task.detached {
                process.waitUntilExit()
                tracker?.didExit(.sync)
                for reader in readers { await reader.value }
                continuation.yield(.finished(exitCode: process.terminationStatus))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// Finds a python3 that can `import requests`.
enum PythonLocator {
    static let candidates = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
        "/usr/bin/python3",
    ]

    /// Drops the `/usr/bin` shims (they open the Command Line Tools installer when the tools are absent).
    static func executableCandidates(_ paths: [String], commandLineToolsInstalled: Bool) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted && (commandLineToolsInstalled || !$0.hasPrefix("/usr/bin/")) }
    }

    static func commandLineToolsInstalled() -> Bool {
        BoundedProcess.run("/usr/bin/xcode-select", ["-p"], timeout: 5)?.status == 0
    }

    static func detect() async -> String? {
        let hasTools = await Task.detached { commandLineToolsInstalled() }.value
        // `command -v` only resolves the name; it never executes the shim.
        let resolved = await Task.detached { BoundedProcess.which("python3") }.value
        let paths = executableCandidates((resolved.map { [$0] } ?? []) + candidates, commandLineToolsInstalled: hasTools)
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            if await hasRequests(path) { return path }
        }
        return nil
    }

    static func hasRequests(_ path: String) async -> Bool {
        await run(path, ["-c", "import requests"]).status == 0
    }

    private static func run(_ exe: String, _ args: [String]) async -> (status: Int32, output: String?) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: (-1, nil)); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(data: data, encoding: .utf8)))
            }
        }
    }
}
