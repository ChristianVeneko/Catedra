import Foundation

/// Runs a provider's CLI (`claude`, `agy`, `opencode`) as a child process and streams normalized events.
/// stdout is parsed incrementally by the provider's parser; stderr is captured and surfaced as an error event on a
/// non-zero exit that produced neither a result nor an error event.
final class CLIAgentRunner: AgentRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private var cancelled: Set<UUID> = []
    private let environment: @Sendable () -> [String: String]
    private let providers: @Sendable (AgentProviderID) -> any AgentProvider
    private let cancellation: CancellationPolicy

    init(environment: @escaping @Sendable () -> [String: String] = { LoginShellEnvironment.childEnvironment() },
         providers: @escaping @Sendable (AgentProviderID) -> any AgentProvider = { AgentProviders.provider(for: $0) },
         cancellation: CancellationPolicy = CancellationPolicy()) {
        self.environment = environment
        self.providers = providers
        self.cancellation = cancellation
    }

    func start(_ request: AgentRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        let provider = providers(request.provider)
        let name = request.provider.displayName
        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: request.executablePath)
            process.arguments = provider.buildArguments(prompt: request.prompt, options: request.options,
                                                        resume: request.resumeSessionId, cwd: request.cwd,
                                                        knownCommands: request.knownCommands)
            process.currentDirectoryURL = request.cwd
            process.standardInput = FileHandle.nullDevice // stdin closed: the CLI can never wait for input
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err

            continuation.onTermination = { [weak self] _ in
                if process.isRunning { self?.escalate(process) }
                self?.forget(request.runID)
            }

            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var env = environment() // may spawn a login shell once; keep off the caller's thread
                for (key, value) in provider.environmentOverrides { env[key] = value }
                let binaryDirectory = URL(fileURLWithPath: request.executablePath).deletingLastPathComponent().path
                env["PATH"] = LoginShellEnvironment.prepending(binaryDirectory, to: env["PATH"])
                process.environment = env
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
                    continuation.yield(.error("No se pudo iniciar \(name): \(error.localizedDescription)"))
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

                var parser = provider.makeParser()
                var sawTerminal = false
                func emit(_ events: [AgentEvent]) {
                    for event in events {
                        switch event {
                        case .result, .error: sawTerminal = true
                        default: break
                        }
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
                emit(parser.complete(exitStatus: process.terminationStatus))
                if process.terminationStatus != 0, !sawTerminal {
                    let detail = stderrBuffer.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = detail.isEmpty
                        ? "\(name) terminó con código \(process.terminationStatus)."
                        : "\(name) terminó con código \(process.terminationStatus): \(String(detail.suffix(800)))"
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
        if let process, process.isRunning { escalate(process) }
    }

    /// SIGINT (clean end of turn), then SIGTERM, then SIGKILL, waiting out each grace period while the process lives.
    private func escalate(_ process: Process) {
        let policy = cancellation
        DispatchQueue.global(qos: .userInitiated).async {
            for step in policy.steps {
                guard process.isRunning else { return }
                switch step.signal {
                case .interrupt: process.interrupt()
                case .terminate: process.terminate()
                case .kill: kill(process.processIdentifier, SIGKILL)
                }
                let deadline = Date().addingTimeInterval(step.wait)
                while process.isRunning, Date() < deadline { usleep(50_000) }
            }
        }
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
