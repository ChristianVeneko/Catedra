import Testing
import Foundation
@testable import Catedra

struct ClaudeCLIAgentRunnerTests {
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
        let runner = ClaudeCLIAgentRunner(environment: { ProcessInfo.processInfo.environment })
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
        let runner = ClaudeCLIAgentRunner(environment: { ProcessInfo.processInfo.environment })
        let events = try await collect(runner.start(request(exe, cwd: cwd)))
        guard case .assistantText(let text)? = events.first else { Issue.record("no text"); return }
        #expect(URL(fileURLWithPath: text).resolvingSymlinksInPath().path == cwd.resolvingSymlinksInPath().path)
    }

    @Test func nonZeroExitWithoutResultSurfacesStderr() async throws {
        let exe = try fakeClaude("echo 'sin sesión' >&2\nexit 3")
        let runner = ClaudeCLIAgentRunner(environment: { ProcessInfo.processInfo.environment })
        let events = try await collect(runner.start(request(exe, cwd: try makeTempDirectory())))
        guard case .error(let message)? = events.last else { Issue.record("no error"); return }
        #expect(message.contains("sin sesión"))
        #expect(message.contains("3"))
    }

    @Test func cancelStopsProcessAndThrowsCancelled() async throws {
        let exe = try fakeClaude("sleep 30")
        let runner = ClaudeCLIAgentRunner(environment: { ProcessInfo.processInfo.environment })
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
        let runner = ClaudeCLIAgentRunner(environment: { ProcessInfo.processInfo.environment })
        let events = try await collect(runner.start(request("/nonexistent/claude", cwd: try makeTempDirectory())))
        guard case .error? = events.first else { Issue.record("expected error"); return }
    }

    /// Real CLI smoke test (cwd = temp dir, never the workspace). Run with:
    /// `TEST_RUNNER_CATEDRA_LIVE_CLAUDE=1 xcodebuild … test` (xcodebuild forwards the TEST_RUNNER_ prefix).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CATEDRA_LIVE_CLAUDE"] == "1"))
    func liveClaudeRepliesOK() async throws {
        let locator = ClaudeLocator()
        let path = try #require(locator.locate())
        let cwd = try makeTempDirectory()
        let req = AgentRequest(runID: UUID(), executablePath: path, cwd: cwd, prompt: "Reply with just OK",
                               resumeSessionId: nil, options: AgentOptions(model: .haiku, permissionMode: .acceptEdits))
        let events = try await collect(ClaudeCLIAgentRunner().start(req))
        let result = events.compactMap { event -> AgentResult? in
            if case .result(let r) = event { r } else { nil }
        }.first
        let r = try #require(result)
        #expect(!r.isError)
        #expect(r.text.contains("OK"))
        #expect(r.sessionId != nil)
    }
}
