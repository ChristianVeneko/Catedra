import Foundation

/// Streams the output of a command the user explicitly started (for example `pip install`). stdin is closed.
struct CommandStreamer: CommandStreaming {
    func run(_ executable: String, arguments: [String]) -> AsyncStream<SyncOutput> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var env = LoginShellEnvironment.childEnvironment()
            env["PYTHONUNBUFFERED"] = "1"
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
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
                continuation.yield(.line("No se pudo ejecutar el comando: \(error.localizedDescription)", isError: true))
                continuation.yield(.finished(exitCode: -1))
                continuation.finish()
                return
            }
            Task.detached {
                process.waitUntilExit()
                for reader in readers { await reader.value }
                continuation.yield(.finished(exitCode: process.terminationStatus))
                continuation.finish()
            }
            continuation.onTermination = { _ in if process.isRunning { process.terminate() } }
        }
    }
}
