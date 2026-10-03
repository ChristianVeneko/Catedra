import Testing
import Foundation
@testable import Catedra

struct ProviderArgumentsTests {
    let cwd = URL(fileURLWithPath: "/tmp/work")

    func args(_ provider: AgentProviderID, model: String? = nil, level: AgentPermissionLevel = .acceptEdits,
              resume: String? = nil, prompt: String = "Hola", known: Set<String> = []) -> [String] {
        AgentProviders.provider(for: provider)
            .buildArguments(prompt: prompt, options: AgentOptions(model: model, permission: level), resume: resume, cwd: cwd, knownCommands: known)
    }

    // MARK: Claude (behavior must stay identical)

    @Test func claudeBaseArguments() {
        #expect(args(.claude) == ["-p", "Hola", "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits"])
    }

    @Test func claudeModelAndResumeAreAppended() {
        let a = args(.claude, model: "haiku", level: .unrestricted, resume: "sess-1")
        #expect(a.suffix(4) == ["--model", "haiku", "--resume", "sess-1"])
        #expect(a.contains("bypassPermissions"))
    }

    @Test func claudePermissionTable() {
        #expect(ClaudeProvider.permissionMode(for: .readOnly) == "plan")
        #expect(ClaudeProvider.permissionMode(for: .acceptEdits) == "acceptEdits")
        #expect(ClaudeProvider.permissionMode(for: .automatic) == "auto")
        #expect(ClaudeProvider.permissionMode(for: .unrestricted) == "bypassPermissions")
    }

    @Test func claudeDefaultModelAndEmptyResumeOmitFlags() {
        #expect(!args(.claude).contains("--model"))
        #expect(!args(.claude, resume: "").contains("--resume"))
    }

    @Test func claudeAddsDirectoriesOfAttachmentsOutsideCwd() {
        let a = args(.claude, prompt: "mira @/Users/x/Desktop/a.png y @/Users/x/Desktop/b.png y @/tmp/work/c.pdf")
        #expect(a.prefix(2) == ["-p", "mira @/Users/x/Desktop/a.png y @/Users/x/Desktop/b.png y @/tmp/work/c.pdf"])
        #expect(a.filter { $0 == "--add-dir" }.count == 1)
        let index = a.firstIndex(of: "--add-dir")!
        #expect(a[index + 1] == "/Users/x/Desktop")
    }

    @Test func claudeWithoutExternalAttachmentsHasNoAddDir() {
        #expect(!args(.claude, prompt: "revisa @material/a.pdf").contains("--add-dir"))
    }

    // MARK: Antigravity

    @Test func antigravityBaseArguments() {
        #expect(args(.antigravity) == ["-p", "Hola", "--output-format", "stream-json", "--mode", "accept-edits"])
    }

    @Test func antigravityPermissionMapping() {
        #expect(args(.antigravity, level: .readOnly).suffix(2) == ["--mode", "plan"])
        #expect(args(.antigravity, level: .unrestricted).last == "--dangerously-skip-permissions")
        #expect(!args(.antigravity, level: .unrestricted).contains("--mode"))
        // "auto" does not exist in Antigravity: it degrades to accept-edits.
        #expect(args(.antigravity, level: .automatic).suffix(2) == ["--mode", "accept-edits"])
    }

    @Test func antigravityModelAndConversationResume() {
        let a = args(.antigravity, model: "gemini-3.1-pro-high", resume: "conv-1")
        #expect(a.suffix(4) == ["--model", "gemini-3.1-pro-high", "--conversation", "conv-1"])
    }

    // MARK: OpenCode

    @Test func openCodeBaseArguments() {
        #expect(args(.opencode) == ["run", "--format", "json", "--dir", "/tmp/work", "--", "Hola"])
    }

    @Test func openCodePermissionMapping() {
        #expect(args(.opencode, level: .readOnly).contains("plan"))
        #expect(args(.opencode, level: .unrestricted).contains("--auto"))
        #expect(!args(.opencode, level: .acceptEdits).contains("--auto"))
        #expect(!args(.opencode, level: .acceptEdits).contains("--agent"))
    }

    @Test func openCodeModelAndSession() {
        let a = args(.opencode, model: "ollama/qwen3", resume: "ses_1")
        #expect(a.contains("-m") && a.contains("ollama/qwen3"))
        #expect(a.contains("--session") && a.contains("ses_1"))
        #expect(a.last == "Hola")
    }

    @Test func openCodeRunsKnownSlashCommandsWithCommandFlag() {
        let a = args(.opencode, prompt: "/deploy staging now", known: ["deploy"])
        #expect(a.contains("--command") && a.contains("deploy"))
        #expect(a.suffix(2) == ["--", "staging now"])
        let bare = args(.opencode, prompt: "/deploy", known: ["deploy"])
        #expect(!bare.contains("--"))
        #expect(args(.opencode, prompt: "/unknown x", known: ["deploy"]).suffix(2) == ["--", "/unknown x"])
    }

    // MARK: Terminal

    @Test func terminalScriptQuotesPathsAndResumes() {
        let script = TerminalLauncher.script(folder: URL(fileURLWithPath: "/a b/it's"), command: ["/x/claude", "--resume", "s1"])
        #expect(script.contains("cd '/a b/it'\\''s' && '/x/claude' '--resume' 's1'"))
        let plain = TerminalLauncher.script(folder: URL(fileURLWithPath: "/a"), command: ["/x/claude"])
        #expect(!plain.contains("--resume"))
    }
}
