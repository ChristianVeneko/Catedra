import Testing
import Foundation
@testable import Catedra

struct ClaudeStreamParserTests {
    @Test func parsesInit() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc","model":"claude-haiku","cwd":"/tmp","tools":["Read"]}"#
        #expect(ClaudeStreamParser.parse(line: line) == [.initialized(sessionId: "abc", model: "claude-haiku")])
    }

    @Test func ignoresNoiseSystemAndRateLimitEvents() {
        for line in [
            #"{"type":"system","subtype":"hook_started","hook":"x"}"#,
            #"{"type":"system","subtype":"hook_response"}"#,
            #"{"type":"system","subtype":"informational","text":"hi"}"#,
            #"{"type":"rate_limit_event","info":{}}"#,
            #"{"type":"something_new","payload":1}"#,
        ] {
            #expect(ClaudeStreamParser.parse(line: line).isEmpty)
        }
    }

    @Test func parsesAssistantTextThinkingAndToolUse() {
        let line = #"""
        {"type":"assistant","message":{"content":[
          {"type":"thinking","thinking":"pienso"},
          {"type":"text","text":"Hola"},
          {"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/b/enunciado.md"}},
          {"type":"tool_use","id":"t2","name":"Bash","input":{"command":"ls -la\nmore"}}
        ]},"session_id":"abc"}
        """#.replacingOccurrences(of: "\n", with: "")
        let events = ClaudeStreamParser.parse(line: line)
        #expect(events == [
            .thinking("pienso"), .assistantText("Hola"),
            .toolUse(id: "t1", name: "Read", summary: "/a/b/enunciado.md"),
            .toolUse(id: "t2", name: "Bash", summary: "ls -la"),
        ])
    }

    @Test func parsesToolResultStringAndBlocks() {
        let s = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}"#
        #expect(ClaudeStreamParser.parse(line: s) == [.toolResult(toolUseId: "t1", isError: false, preview: "ok")])
        let b = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"a"},{"type":"text","text":"b"}],"is_error":true}]}}"#
        #expect(ClaudeStreamParser.parse(line: b) == [.toolResult(toolUseId: "t2", isError: true, preview: "a\nb")])
    }

    @Test func truncatesLongPreviews() {
        let long = String(repeating: "x", count: 5000)
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":""# + long + #""}]}}"#
        guard case .toolResult(_, _, let preview)? = ClaudeStreamParser.parse(line: line).first else { Issue.record("no event"); return }
        #expect(preview.count <= ClaudeStreamParser.previewLimit + 1)
    }

    @Test func parsesResultWithDenials() {
        let line = #"""
        {"type":"result","subtype":"success","is_error":false,"result":"Listo","session_id":"abc","total_cost_usd":0.0123,"duration_ms":4200,
         "permission_denials":[{"tool_name":"Bash","tool_use_id":"t9","tool_input":{"command":"rm -rf x"}}]}
        """#.replacingOccurrences(of: "\n", with: "")
        let events = ClaudeStreamParser.parse(line: line)
        #expect(events == [
            .denials([PermissionDenial(toolName: "Bash", summary: "rm -rf x")]),
            .result(AgentResult(isError: false, subtype: "success", text: "Listo", sessionId: "abc", costUSD: 0.0123, durationMs: 4200)),
        ])
    }

    @Test func parsesErrorResultWithoutOptionalFields() {
        let line = #"{"type":"result","subtype":"error_max_turns","is_error":true}"#
        #expect(ClaudeStreamParser.parse(line: line) == [
            .result(AgentResult(isError: true, subtype: "error_max_turns", text: "", sessionId: nil, costUSD: nil, durationMs: nil))
        ])
    }

    @Test func malformedLinesAreSkipped() {
        #expect(ClaudeStreamParser.parse(line: "not json").isEmpty)
        #expect(ClaudeStreamParser.parse(line: "").isEmpty)
        #expect(ClaudeStreamParser.parse(line: "[1,2]").isEmpty)
        #expect(ClaudeStreamParser.parse(line: #"{"type":"assistant","message":5}"#).isEmpty)
    }

    @Test func feedHandlesPartialLinesAndSplitUTF8() {
        var parser = ClaudeStreamParser()
        let full = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Tarea ñandú"}]}}"# + "\n"
        let bytes = Array(full.utf8)
        // split in the middle of the two-byte "ñ"
        let cut = bytes.firstIndex(of: 0xC3)! + 1
        #expect(parser.feed(Data(bytes[..<cut])).isEmpty)
        #expect(parser.feed(Data(bytes[cut...])) == [.assistantText("Tarea ñandú")])
    }

    @Test func feedHandlesMultipleLinesAndFlushesTail() {
        var parser = ClaudeStreamParser()
        let a = #"{"type":"system","subtype":"init","session_id":"s"}"#
        let b = #"{"type":"result","subtype":"success","is_error":false,"result":"x"}"#
        let events = parser.feed(Data((a + "\n" + b).utf8))
        #expect(events == [.initialized(sessionId: "s", model: nil)])
        let tail = parser.finish()
        #expect(tail.count == 1)
    }

    @Test func summarizesToolInputs() {
        #expect(ToolSummary.summarize(name: "Glob", input: ["pattern": "**/*.md"]) == "**/*.md")
        #expect(ToolSummary.summarize(name: "Skill", input: ["skill": "normas-uft"]) == "normas-uft")
        #expect(ToolSummary.summarize(name: "Weird", input: ["foo": 3, "bar": "texto"]) == "texto")
        #expect(ToolSummary.summarize(name: "Weird", input: [:]) == "")
    }
}

struct AgentStreamCommandsTests {
    @Test func parsesCommandsChanged() {
        let line = #"{"type":"system","subtype":"commands_changed","commands":[{"name":"normas-uft","description":"Normas","argumentHint":"[name]"},{"name":"clear","description":"Limpia","aliases":["reset","new"],"builtin":true},{"description":"sin nombre"}]}"#
        let events = ClaudeStreamParser.parse(line: line)
        #expect(events == [.commandsCatalog([
            SlashCommand(name: "normas-uft", description: "Normas", argumentHint: "[name]", aliases: [], kind: .skill),
            SlashCommand(name: "clear", description: "Limpia", argumentHint: nil, aliases: ["reset", "new"], kind: .builtin),
        ], complete: true)])
    }

    @Test func initFallsBackToSlashCommandNamesExcludingTerminalOnes() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc","model":"m","slash_commands":["compact","normas-uft","doctor"],"terminal_slash_commands":["doctor"]}"#
        let events = ClaudeStreamParser.parse(line: line)
        #expect(events.count == 2)
        #expect(events[0] == .initialized(sessionId: "abc", model: "m"))
        guard case .commandsCatalog(let commands, let complete) = events[1] else { Issue.record("expected catalog"); return }
        #expect(complete == false)
        #expect(commands.map(\.name) == ["compact", "normas-uft"])
        #expect(commands[0].kind == .builtin && commands[1].kind == .skill)
    }

    @Test func catalogEventsDoNotEnterTheTranscript() {
        var run = AgentRun(scope: AgentScopeRef(kind: .course, folder: "c", title: "C"), prompt: "p", recipeID: nil, recipeTitle: nil, at: .now)
        run.apply(.commandsCatalog([], complete: true), at: .now)
        #expect(run.transcript == [.userPrompt("p")])
    }
}
