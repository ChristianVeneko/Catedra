import Testing
import Foundation
@testable import Catedra

struct AgentStreamParserTests {
    @Test func parsesInit() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc","model":"claude-haiku","cwd":"/tmp","tools":["Read"]}"#
        #expect(AgentStreamParser.parse(line: line) == [.initialized(sessionId: "abc", model: "claude-haiku")])
    }

    @Test func ignoresNoiseSystemAndRateLimitEvents() {
        for line in [
            #"{"type":"system","subtype":"hook_started","hook":"x"}"#,
            #"{"type":"system","subtype":"hook_response"}"#,
            #"{"type":"system","subtype":"informational","text":"hi"}"#,
            #"{"type":"rate_limit_event","info":{}}"#,
            #"{"type":"something_new","payload":1}"#,
        ] {
            #expect(AgentStreamParser.parse(line: line).isEmpty)
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
        let events = AgentStreamParser.parse(line: line)
        #expect(events == [
            .thinking("pienso"), .assistantText("Hola"),
            .toolUse(id: "t1", name: "Read", summary: "/a/b/enunciado.md"),
            .toolUse(id: "t2", name: "Bash", summary: "ls -la"),
        ])
    }

    @Test func parsesToolResultStringAndBlocks() {
        let s = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}"#
        #expect(AgentStreamParser.parse(line: s) == [.toolResult(toolUseId: "t1", isError: false, preview: "ok")])
        let b = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"a"},{"type":"text","text":"b"}],"is_error":true}]}}"#
        #expect(AgentStreamParser.parse(line: b) == [.toolResult(toolUseId: "t2", isError: true, preview: "a\nb")])
    }

    @Test func truncatesLongPreviews() {
        let long = String(repeating: "x", count: 5000)
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":""# + long + #""}]}}"#
        guard case .toolResult(_, _, let preview)? = AgentStreamParser.parse(line: line).first else { Issue.record("no event"); return }
        #expect(preview.count <= AgentStreamParser.previewLimit + 1)
    }

    @Test func parsesResultWithDenials() {
        let line = #"""
        {"type":"result","subtype":"success","is_error":false,"result":"Listo","session_id":"abc","total_cost_usd":0.0123,"duration_ms":4200,
         "permission_denials":[{"tool_name":"Bash","tool_use_id":"t9","tool_input":{"command":"rm -rf x"}}]}
        """#.replacingOccurrences(of: "\n", with: "")
        let events = AgentStreamParser.parse(line: line)
        #expect(events == [
            .denials([PermissionDenial(toolName: "Bash", summary: "rm -rf x")]),
            .result(AgentResult(isError: false, subtype: "success", text: "Listo", sessionId: "abc", costUSD: 0.0123, durationMs: 4200)),
        ])
    }

    @Test func parsesErrorResultWithoutOptionalFields() {
        let line = #"{"type":"result","subtype":"error_max_turns","is_error":true}"#
        #expect(AgentStreamParser.parse(line: line) == [
            .result(AgentResult(isError: true, subtype: "error_max_turns", text: "", sessionId: nil, costUSD: nil, durationMs: nil))
        ])
    }

    @Test func malformedLinesAreSkipped() {
        #expect(AgentStreamParser.parse(line: "not json").isEmpty)
        #expect(AgentStreamParser.parse(line: "").isEmpty)
        #expect(AgentStreamParser.parse(line: "[1,2]").isEmpty)
        #expect(AgentStreamParser.parse(line: #"{"type":"assistant","message":5}"#).isEmpty)
    }

    @Test func feedHandlesPartialLinesAndSplitUTF8() {
        var parser = AgentStreamParser()
        let full = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Tarea ñandú"}]}}"# + "\n"
        let bytes = Array(full.utf8)
        // split in the middle of the two-byte "ñ"
        let cut = bytes.firstIndex(of: 0xC3)! + 1
        #expect(parser.feed(Data(bytes[..<cut])).isEmpty)
        #expect(parser.feed(Data(bytes[cut...])) == [.assistantText("Tarea ñandú")])
    }

    @Test func feedHandlesMultipleLinesAndFlushesTail() {
        var parser = AgentStreamParser()
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
