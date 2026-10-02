import Testing
import Foundation
@testable import Catedra

struct AgentProviderTests {
    @Test func providerIdsAndNames() {
        #expect(AgentProviderID.allCases == [.claude, .antigravity, .opencode])
        #expect(AgentProviderID.antigravity.binaryName == "agy")
        #expect(AgentProviderID.antigravity.displayName == "Antigravity")
        #expect(AgentProviderID.claude.installHint == "curl -fsSL https://claude.ai/install.sh | bash")
        #expect(AgentProviderID.opencode.installHint == "curl -fsSL https://opencode.ai/install | bash")
    }

    @Test func onlyOpenCodeCarriesTheTermsWarning() {
        #expect(AgentProviderID.opencode.tosWarning?.contains("Claude Pro/Max") == true)
        #expect(AgentProviderID.claude.tosWarning == nil)
        #expect(AgentProviderID.antigravity.tosWarning == nil)
    }

    @Test func supportedPermissionTables() {
        #expect(AgentProviderID.claude.supportedPermissions == [.readOnly, .acceptEdits, .automatic, .unrestricted])
        #expect(AgentProviderID.antigravity.supportedPermissions == [.readOnly, .acceptEdits, .unrestricted])
        #expect(AgentProviderID.opencode.supportedPermissions == [.readOnly, .acceptEdits, .unrestricted])
    }

    @Test func unsupportedLevelFallsBackToAcceptEdits() {
        #expect(AgentProviderID.antigravity.normalized(.automatic) == .acceptEdits)
        #expect(AgentProviderID.claude.normalized(.automatic) == .automatic)
    }

    @Test func legacyStoredPermissionValuesStillDecode() {
        #expect(AgentPermissionLevel(storedValue: "acceptEdits") == .acceptEdits)
        #expect(AgentPermissionLevel(storedValue: "auto") == .automatic)
        #expect(AgentPermissionLevel(storedValue: "bypassPermissions") == .unrestricted)
        #expect(AgentPermissionLevel(storedValue: "readOnly") == .readOnly)
        #expect(AgentPermissionLevel(storedValue: "???") == nil)
    }

    @Test func terminalResumeArgumentsPerProvider() {
        #expect(AgentProviderID.claude.terminalResumeArguments(sessionId: "s") == ["--resume", "s"])
        #expect(AgentProviderID.antigravity.terminalResumeArguments(sessionId: "s") == ["--conversation", "s"])
        #expect(AgentProviderID.opencode.terminalResumeArguments(sessionId: "s") == ["--session", "s"])
        #expect(AgentProviderID.opencode.terminalResumeArguments(sessionId: nil).isEmpty)
        #expect(AgentProviderID.claude.terminalResumeArguments(sessionId: "").isEmpty)
    }

    @Test func sectionTitlesAreProviderSpecific() {
        #expect(AgentProviderID.claude.slashSectionTitle == "Comandos de Claude Code")
        #expect(AgentProviderID.antigravity.slashSectionTitle == "Skills / Comandos de Antigravity")
        #expect(AgentProviderID.opencode.slashSectionTitle == "Skills / Comandos de OpenCode")
    }

    // MARK: - Cancellation policy

    @Test func cancellationEscalatesInterruptThenTerminateThenKill() {
        let policy = CancellationPolicy(interruptGrace: 4, terminateGrace: 3)
        #expect(policy.signal(afterElapsed: 0) == .interrupt)
        #expect(policy.signal(afterElapsed: 3.9) == .interrupt)
        #expect(policy.signal(afterElapsed: 4) == .terminate)
        #expect(policy.signal(afterElapsed: 6.9) == .terminate)
        #expect(policy.signal(afterElapsed: 7) == .kill)
        #expect(policy.steps.map(\.signal) == [.interrupt, .terminate, .kill])
        #expect(policy.steps.map(\.wait) == [4, 3, 0])
    }

    // MARK: - Parsing helpers

    @Test func agyModelsListSkipsHeaderAndParsesTabSeparatedLines() {
        let output = "Fetching available models...\ngemini-3.8-flash-high\tGemini 3.8 Flash (High)\nclaude-sonnet-4-6\tClaude Sonnet 4.6 (Thinking)\n\nbasura sin tab\n"
        #expect(ModelListParser.antigravity(output) == [
            AgentModelOption(id: "gemini-3.8-flash-high", label: "Gemini 3.8 Flash (High)"),
            AgentModelOption(id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6 (Thinking)"),
        ])
    }

    @Test func openCodeModelsAreProviderSlashModelLines() {
        let output = "ollama/qwen3:8b\nanthropic/claude-sonnet-4\n\nnot a model\n"
        #expect(ModelListParser.opencode(output).map(\.id) == ["ollama/qwen3:8b", "anthropic/claude-sonnet-4"])
    }

    @Test func versionIsExtractedFromTypicalOutputs() {
        #expect(VersionParser.parse("2.1.288 (Claude Code)") == "2.1.288")
        #expect(VersionParser.parse("1.18.18\n") == "1.18.18")
        #expect(VersionParser.parse("agy version v1.2.15") == "1.2.15")
        #expect(VersionParser.parse("no version here") == nil)
    }

    @Test func prependingDirectoryToPathAvoidsDuplicates() {
        #expect(LoginShellEnvironment.prepending("/n/bin", to: "/a:/b") == "/n/bin:/a:/b")
        #expect(LoginShellEnvironment.prepending("/a", to: "/a:/b") == "/a:/b")
        #expect(LoginShellEnvironment.prepending("/n", to: nil) == "/n")
    }
}
