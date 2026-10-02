import Testing
import Foundation
@testable import Catedra

struct CLIAgentRunnerTests {
    /// Writes an executable shell script acting as a fake `claude`.
    func fakeClaude(_ body: String) throws -> String {
        let dir = try makeTempDirectory()
        let url = dir.appendingPathComponent("claude")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func request(_ exe: String, cwd: URL) -> AgentRequest {
        AgentRequest(runID: UUID(), executablePath: exe, cwd: cwd, prompt: "hola", resumeSessionId: nil, options: AgentOptions())
    }

    func collect(_ stream: AsyncThrowingStream<AgentEvent, Error>) async throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        for try await e in stream { events.append(e) }
        return events
    }

    @Test func streamsEventsFromStdoutInOrder() async throws {
        let exe = try fakeClaude(#"""
        echo '{"type":"system","subtype":"init","session_id":"s1","model":"m"}'
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"hola"}]}}'
        echo 'garbage'
        echo '{"type":"result","subtype":"success","is_error":false,"result":"hola","session_id":"s1","total_cost_usd":0.01}'
        """#)
        let cwd = try makeTempDirectory()
        let runner = CLIAgentRunner(environment: { ProcessInfo.processInfo.environment }, cancellation: CancellationPolicy(interruptGrace: 0.3, terminateGrace: 0.3))
        let events = try await collect(runner.start(request(exe, cwd: cwd)))
        #expect(events.count == 3)
        #expect(events.first == .initialized(sessionId: "s1", model: "m"))
        if case .result(let r)? = events.last { #expect(!r.isError) } else { Issue.record("no result") }
    }

    @Test func runsInRequestedWorkingDirectory() async throws {
        let exe = try fakeClaude(#"""
        printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$(pwd -P)"
        """#)
        let cwd = try makeTempDirectory()
        let runner = CLIAgentRunner(environment: { ProcessInfo.processInfo.environment }, cancellation: CancellationPolicy(interruptGrace: 0.3, terminateGrace: 0.3))
        let events = try await collect(runner.start(request(exe, cwd: cwd)))
        guard case .assistantText(let text)? = events.first else { Issue.record("no text"); return }
        #expect(URL(fileURLWithPath: text).resolvingSymlinksInPath().path == cwd.resolvingSymlinksInPath().path)
    }

    @Test func nonZeroExitWithoutResultSurfacesStderr() async throws {
        let exe = try fakeClaude("echo 'sin sesión' >&2\nexit 3")
        let runner = CLIAgentRunner(environment: { ProcessInfo.processInfo.environment }, cancellation: CancellationPolicy(interruptGrace: 0.3, terminateGrace: 0.3))
        let events = try await collect(runner.start(request(exe, cwd: try makeTempDirectory())))
        guard case .error(let message)? = events.last else { Issue.record("no error"); return }
        #expect(message.contains("sin sesión"))
        #expect(message.contains("3"))
    }

    @Test func cancelStopsProcessAndThrowsCancelled() async throws {
        let exe = try fakeClaude("sleep 30")
        let runner = CLIAgentRunner(environment: { ProcessInfo.processInfo.environment }, cancellation: CancellationPolicy(interruptGrace: 0.3, terminateGrace: 0.3))
        let req = request(exe, cwd: try makeTempDirectory())
        let stream = runner.start(req)
        Task { try? await Task.sleep(nanoseconds: 300_000_000); runner.cancel(runID: req.runID) }
        do {
            _ = try await collect(stream)
            Issue.record("expected cancellation")
        } catch let error as AgentRunnerError {
            #expect(error == .cancelled)
        }
    }

    @Test func missingExecutableYieldsErrorEvent() async throws {
        let runner = CLIAgentRunner(environment: { ProcessInfo.processInfo.environment }, cancellation: CancellationPolicy(interruptGrace: 0.3, terminateGrace: 0.3))
        let events = try await collect(runner.start(request("/nonexistent/claude", cwd: try makeTempDirectory())))
        guard case .error? = events.first else { Issue.record("expected error"); return }
    }

    /// Real CLI smoke test (cwd = temp dir, never the workspace). Run with:
    /// `TEST_RUNNER_CATEDRA_LIVE_CLAUDE=1 xcodebuild … test` (xcodebuild forwards the TEST_RUNNER_ prefix).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CATEDRA_LIVE_CLAUDE"] == "1"))
    func liveClaudeRepliesOK() async throws {
        let path = try #require(BinaryLocator(provider: .claude).locate())
        let cwd = try makeTempDirectory()
        let req = AgentRequest(runID: UUID(), executablePath: path, cwd: cwd, prompt: "Reply with just OK",
                               resumeSessionId: nil, options: AgentOptions(model: "haiku", permission: .acceptEdits))
        let events = try await collect(CLIAgentRunner().start(req))
        let result = events.compactMap { event -> AgentResult? in
            if case .result(let r) = event { r } else { nil }
        }.first
        let r = try #require(result)
        #expect(!r.isError)
        #expect(r.text.contains("OK"))
        #expect(r.sessionId != nil)
    }

    // MARK: - Other providers (fake binaries)

    func providerRequest(_ provider: AgentProviderID, _ exe: String, cwd: URL) -> AgentRequest {
        AgentRequest(runID: UUID(), provider: provider, executablePath: exe, cwd: cwd, prompt: "hola", resumeSessionId: nil, options: AgentOptions())
    }

    func runner() -> CLIAgentRunner {
        CLIAgentRunner(environment: { ProcessInfo.processInfo.environment },
                       cancellation: CancellationPolicy(interruptGrace: 0.3, terminateGrace: 0.3))
    }

    @Test func openCodeStreamGetsASyntheticSuccessResultOnCleanExit() async throws {
        let exe = try fakeClaude(#"""
        echo '{"type":"step_start","timestamp":1,"sessionID":"ses_1","part":{}}'
        echo '{"type":"text","timestamp":2,"sessionID":"ses_1","part":{"text":"OK"}}'
        echo '{"type":"step_finish","timestamp":3,"sessionID":"ses_1","part":{"cost":0.01,"tokens":{"input":5,"output":2}}}'
        """#)
        let events = try await collect(runner().start(providerRequest(.opencode, exe, cwd: try makeTempDirectory())))
        guard case .result(let r)? = events.last else { Issue.record("no result"); return }
        #expect(!r.isError && r.text == "OK" && r.sessionId == "ses_1")
    }

    @Test func openCodeErrorEventWithNonZeroExitIsReportedOnce() async throws {
        let exe = try fakeClaude(#"""
        echo '{"type":"error","timestamp":1,"sessionID":"ses_1","error":{"name":"APIError","data":{"message":"sin conexion"}}}'
        echo 'ruido' >&2
        exit 1
        """#)
        let events = try await collect(runner().start(providerRequest(.opencode, exe, cwd: try makeTempDirectory())))
        #expect(events.filter { if case .error = $0 { true } else { false } }.count == 1)
        #expect(!events.contains { if case .result = $0 { true } else { false } })
    }

    @Test func antigravityStreamRunsThroughTheSameRunner() async throws {
        let exe = try fakeClaude(#"""
        echo '{"event":"init","conversation_id":"c1","init":{}}'
        echo '{"event":"result","result":{"conversation_id":"c1","status":"SUCCESS","response":"OK"}}'
        """#)
        let events = try await collect(runner().start(providerRequest(.antigravity, exe, cwd: try makeTempDirectory())))
        #expect(events.first == .initialized(sessionId: "c1", model: nil))
        guard case .result(let r)? = events.last else { Issue.record("no result"); return }
        #expect(!r.isError)
    }

    @Test func childPathStartsWithTheBinaryDirectory() async throws {
        let exe = try fakeClaude(#"""
        printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "${PATH%%:*}"
        """#)
        let events = try await collect(runner().start(request(exe, cwd: try makeTempDirectory())))
        guard case .assistantText(let first)? = events.first else { Issue.record("no text"); return }
        #expect(first == URL(fileURLWithPath: exe).deletingLastPathComponent().path)
    }

    // MARK: - Live smoke tests

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CATEDRA_LIVE_AGY"] == "1"))
    func liveAntigravityRepliesOK() async throws {
        let path = try #require(BinaryLocator(provider: .antigravity).locate())
        let req = AgentRequest(runID: UUID(), provider: .antigravity, executablePath: path, cwd: try makeTempDirectory(),
                               prompt: "Reply with just OK", resumeSessionId: nil, options: AgentOptions())
        let events = try await collect(CLIAgentRunner().start(req))
        let r = try #require(events.compactMap { event -> AgentResult? in if case .result(let r) = event { r } else { nil } }.first)
        #expect(!r.isError)
        #expect(r.text.contains("OK"))
        #expect(r.sessionId != nil)
    }

    /// OpenCode on this machine points at a local Ollama that is normally down: the run must fail cleanly (an `error`
    /// event, a failed run, a process that exits) instead of hanging. OpenCode retries for about a minute first.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CATEDRA_LIVE_OPENCODE"] == "1"))
    func liveOpenCodeSurfacesProviderErrorsCleanly() async throws {
        let path = try #require(BinaryLocator(provider: .opencode).locate())
        let req = AgentRequest(runID: UUID(), provider: .opencode, executablePath: path, cwd: try makeTempDirectory(),
                               prompt: "Reply with just OK", resumeSessionId: nil, options: AgentOptions())
        let live = CLIAgentRunner()
        let watchdog = Task { try await Task.sleep(for: .seconds(150)); live.cancel(runID: req.runID) }
        defer { watchdog.cancel() }
        var run = AgentRun(provider: .opencode, scope: AgentScopeRef(kind: .course, folder: "x", title: "x"), prompt: "p",
                           recipeID: nil, recipeTitle: nil, at: .now)
        var timedOut = false
        do {
            for try await event in live.start(req) { run.apply(event, at: .now) }
        } catch AgentRunnerError.cancelled { timedOut = true }
        #expect(!timedOut, "OpenCode did not exit within 150 s")
        if run.status == .succeeded {
            Issue.record("OpenCode answered; the provider error path was not exercised")
        } else {
            #expect(run.status == .failed)
            #expect(run.transcript.contains { if case .error = $0 { true } else { false } })
        }
    }
}
