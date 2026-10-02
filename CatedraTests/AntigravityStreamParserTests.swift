import Testing
import Foundation
@testable import Catedra

struct AntigravityStreamParserTests {
    func parse(_ lines: [String]) -> [AgentEvent] {
        var parser = AntigravityStreamParser()
        var events = lines.flatMap { parser.feed(Data(($0 + "\n").utf8)) }
        events += parser.finish()
        return events
    }

    let cid = "30c5"

    @Test func initCarriesConversationId() {
        let events = parse([#"{"event":"init","conversation_id":"30c5","init":{"cwd":"/tmp","permission_mode":"accept-edits"}}"#])
        #expect(events == [.initialized(sessionId: "30c5", model: nil)])
    }

    @Test func textDeltasOfOneStepBecomeOneAssistantBlock() {
        let events = parse([
            #"{"event":"step_update","step_update":{"conversation_id":"30c5","step_index":1,"state":"ACTIVE","step_type":"agent_response","text_delta":"Ho"}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"30c5","step_index":1,"state":"ACTIVE","step_type":"agent_response","text_delta":"la"}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"30c5","step_index":1,"state":"DONE","step_type":"agent_response","text_delta":"\n","usage":{"input_tokens":1}}}"#,
        ])
        #expect(events == [.assistantText("Hola")])
    }

    @Test func userInputStepsAreIgnored() {
        #expect(parse([#"{"event":"step_update","step_update":{"step_index":0,"state":"DONE","step_type":"user_input"}}"#]).isEmpty)
    }

    @Test func toolStepEmitsUseOnActiveAndResultOnDone() {
        let events = parse([
            #"{"event":"step_update","step_update":{"step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"view_file","tool_info":{"name":"view_file","parameters":{"AbsolutePath":"/tmp/a.txt"}}}}"#,
            #"{"event":"step_update","step_update":{"step_index":2,"state":"DONE","step_type":"tool","tool_name":"view_file","tool_info":{"name":"view_file","parameters":{"AbsolutePath":"/tmp/a.txt"},"output":"2 lines, 5 bytes"}}}"#,
        ])
        #expect(events == [
            .toolUse(id: "step-2", name: "view_file", summary: "/tmp/a.txt"),
            .toolResult(toolUseId: "step-2", isError: false, preview: "2 lines, 5 bytes"),
        ])
    }

    @Test func failedToolStateIsAnError() {
        let events = parse([
            #"{"event":"step_update","step_update":{"step_index":3,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":{"parameters":{"CommandLine":"ls"}}}}"#,
            #"{"event":"step_update","step_update":{"step_index":3,"state":"ERROR","step_type":"tool","tool_name":"run_command","tool_info":{"output":"denied"}}}"#,
        ])
        #expect(events.last == .toolResult(toolUseId: "step-3", isError: true, preview: "denied"))
    }

    @Test func pendingTextIsFlushedBeforeATool() {
        let events = parse([
            #"{"event":"step_update","step_update":{"step_index":1,"state":"ACTIVE","step_type":"agent_response","text_delta":"voy"}}"#,
            #"{"event":"step_update","step_update":{"step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"list_dir","tool_info":{"parameters":{"DirectoryPath":"/x"}}}}"#,
        ])
        #expect(events == [.assistantText("voy"), .toolUse(id: "step-2", name: "list_dir", summary: "/x")])
    }

    @Test func successResultMapsUsageAndSession() {
        let events = parse([#"{"event":"result","result":{"conversation_id":"30c5","status":"SUCCESS","response":"OK\n","duration_seconds":7.5,"usage":{"input_tokens":10,"output_tokens":3,"total_tokens":13}}}"#])
        #expect(events == [.result(AgentResult(isError: false, subtype: "SUCCESS", text: "OK\n", sessionId: "30c5", costUSD: nil,
                                               durationMs: 7500, inputTokens: 10, outputTokens: 3))])
    }

    @Test func nonSuccessResultFails() {
        let events = parse([#"{"event":"result","result":{"conversation_id":"c","status":"ERROR","response":"boom"}}"#])
        guard case .result(let r)? = events.last else { Issue.record("no result"); return }
        #expect(r.isError)
        #expect(r.subtype == "ERROR")
    }

    @Test func toleratesGarbageAndUnknownEvents() {
        #expect(parse(["not json", "", "[1]", #"{"event":"telemetry","x":1}"#, #"{"nope":true}"#,
                       #"{"event":"step_update","step_update":{"step_index":9,"state":"ACTIVE","step_type":"mystery"}}"#,
                       #"{"event":"step_update"}"#]).isEmpty)
    }

    @Test func partialLinesAcrossChunksAreBuffered() {
        var parser = AntigravityStreamParser()
        let line = #"{"event":"init","conversation_id":"abc","init":{}}"#
        #expect(parser.feed(Data(line.prefix(10).utf8)).isEmpty)
        #expect(parser.feed(Data((String(line.dropFirst(10)) + "\n").utf8)) == [.initialized(sessionId: "abc", model: nil)])
    }

    @Test func realRecordedStreamProducesATranscript() throws {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: "antigravity-stream", withExtension: "ndjson"))
        let events = parse(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init))
        #expect(events.first == .initialized(sessionId: "a0335971-b532-419b-9fe7-53af8bd398f0", model: nil))
        #expect(events.contains(.assistantText("hola")))
        #expect(events.contains { if case .toolUse(_, "view_file", _) = $0 { true } else { false } })
        guard case .result(let r)? = events.last else { Issue.record("no result"); return }
        #expect(!r.isError)
        #expect(r.inputTokens == 25239)
    }
}

final class FixtureAnchor {}
