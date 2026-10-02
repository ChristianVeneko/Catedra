import Foundation

/// Runs `claude -p … --output-format stream-json` as a child process and streams normalized events.
/// stdout is parsed incrementally; stderr is captured and surfaced as an error event on a non-zero exit.
final class ClaudeCLIAgentRunner: AgentRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private var cancelled: Set<UUID> = []
    private let environment: @Sendable () -> [String: String]

    init(environment: @escaping @Sendable () -> [String: String] = { LoginShellEnvironment.childEnvironment() }) {
        self.environment = environment
    }

    func start(_ request: AgentRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: request.executablePath)
            process.arguments = ClaudeCommand.arguments(for: request)
            process.currentDirectoryURL = request.cwd
            process.standardInput = FileHandle.nullDevice // stdin closed: the CLI can never wait for input
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err

            continuation.onTermination = { [weak self] _ in
                if process.isRunning { process.terminate() }
                self?.forget(request.runID)
            }

            DispatchQueue.global(qos: .userInitiated).async { [self] in
                process.environment = environment() // may spawn a login shell once; keep off the caller's thread
                lock.lock()
                let alreadyCancelled = cancelled.contains(request.runID)
                if !alreadyCancelled { processes[request.runID] = process }
                lock.unlock()
                if alreadyCancelled {
                    _ = takeCancelled(request.runID)
                    continuation.finish(throwing: AgentRunnerError.cancelled)
                    return
                }

                let stderrBuffer = LockedText()
                let errorDrained = DispatchSemaphore(value: 0)
                do { try process.run() } catch {
                    forget(request.runID)
                    continuation.yield(.error("No se pudo iniciar Claude Code: \(error.localizedDescription)"))
                    continuation.finish()
                    return
                }
                DispatchQueue.global(qos: .utility).async {
                    while true {
                        let data = err.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        stderrBuffer.append(String(decoding: data, as: UTF8.self))
                    }
                    errorDrained.signal()
                }

                var parser = AgentStreamParser()
                var sawResult = false
                func emit(_ events: [AgentEvent]) {
                    for event in events {
                        if case .result = event { sawResult = true }
                        continuation.yield(event)
                    }
                }
                while true {
                    let data = out.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    emit(parser.feed(data))
                }
                emit(parser.finish())
                process.waitUntilExit()
                errorDrained.wait()

                let wasCancelled = takeCancelled(request.runID)
                forget(request.runID)
                if wasCancelled {
                    continuation.finish(throwing: AgentRunnerError.cancelled)
                    return
                }
                if process.terminationStatus != 0, !sawResult {
                    let detail = stderrBuffer.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = detail.isEmpty
                        ? "Claude Code terminó con código \(process.terminationStatus)."
                        : "Claude Code terminó con código \(process.terminationStatus): \(String(detail.suffix(800)))"
                    continuation.yield(.error(message))
                }
                continuation.finish()
            }
        }
    }

    func cancel(runID: UUID) {
        lock.lock()
        cancelled.insert(runID)
        let process = processes[runID]
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    private func forget(_ id: UUID) {
        lock.lock(); processes[id] = nil; lock.unlock()
    }

    private func takeCancelled(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled.remove(id) != nil
    }
}

private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ more: String) { lock.lock(); text += more; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}
