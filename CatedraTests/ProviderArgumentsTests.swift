import Testing
import Foundation
@testable import Catedra

struct ClaudeCommandTests {
    func request(model: AgentModel = .default, mode: AgentPermissionMode = .acceptEdits, resume: String? = nil) -> AgentRequest {
        AgentRequest(runID: UUID(), executablePath: "/x/claude", cwd: URL(fileURLWithPath: "/tmp"), prompt: "Hola",
                     resumeSessionId: resume, options: AgentOptions(model: model, permissionMode: mode))
    }

    @Test func baseArguments() {
        #expect(ClaudeCommand.arguments(for: request()) == [
            "-p", "Hola", "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
        ])
    }

    @Test func modelAndResumeAreAppended() {
        let args = ClaudeCommand.arguments(for: request(model: .haiku, mode: .bypassPermissions, resume: "sess-1"))
        #expect(args.suffix(4) == ["--model", "haiku", "--resume", "sess-1"])
        #expect(args.contains("bypassPermissions"))
    }

    @Test func defaultModelOmitsFlag() {
        #expect(!ClaudeCommand.arguments(for: request(model: .default)).contains("--model"))
    }

    @Test func emptyResumeIdIsIgnored() {
        #expect(!ClaudeCommand.arguments(for: request(resume: "")).contains("--resume"))
    }

    @Test func terminalScriptQuotesPathsAndResumes() {
        let script = TerminalLauncher.script(folder: URL(fileURLWithPath: "/a b/it's"), executablePath: "/x/claude", sessionId: "s1")
        #expect(script.contains("cd '/a b/it'\\''s' && '/x/claude' --resume 's1'"))
        let plain = TerminalLauncher.script(folder: URL(fileURLWithPath: "/a"), executablePath: "/x/claude", sessionId: nil)
        #expect(!plain.contains("--resume"))
    }
}
