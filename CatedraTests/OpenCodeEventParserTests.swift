import Testing
import Foundation
@testable import Catedra

struct OpenCodeEventParserTests {
    func run(_ lines: [String], exit: Int32 = 0) -> [AgentEvent] {
        var parser = OpenCodeEventParser()
        var events = lines.flatMap { parser.feed(Data(($0 + "\n").utf8)) }
        events += parser.finish()
        events += parser.complete(exitStatus: exit)
        return events
    }

    let stepStart = #"{"type":"step_start","timestamp":1000,"sessionID":"ses_1","part":{"type":"step-start","id":"p1"}}"#
    let text = #"{"type":"text","timestamp":1500,"sessionID":"ses_1","part":{"type":"text","text":"  OK  ","time":{"start":1,"end":2}}}"#
    let reasoning = #"{"type":"reasoning","timestamp":1200,"sessionID":"ses_1","part":{"type":"reasoning","text":"pienso","time":{"start":1,"end":2}}}"#
    let tool = #"{"type":"tool_use","timestamp":1300,"sessionID":"ses_1","part":{"type":"tool","callID":"c1","tool":"read","state":{"status":"completed","input":{"filePath":"/tmp/a.txt"},"output":"hola","title":"a.txt"}}}"#
    let toolError = #"{"type":"tool_use","timestamp":1300,"sessionID":"ses_1","part":{"type":"tool","callID":"c2","tool":"bash","state":{"status":"error","input":{"command":"rm x"},"error":"The user rejected permission to use this specific tool call."}}}"#
    let stepFinish = #"{"type":"step_finish","timestamp":2000,"sessionID":"ses_1","part":{"type":"step-finish","reason":"stop","cost":0.002,"tokens":{"input":100,"output":20,"reasoning":5,"cache":{"read":3,"write":0}}}}"#

    @Test func firstEventInitializesTheSession() {
        let events = run([stepStart])
        #expect(events.first == .initialized(sessionId: "ses_1", model: nil))
        #expect(events.filter { if case .initialized = $0 { true } else { false } }.count == 1)
    }

    @Test func textAndReasoningMap() {
        let events = run([stepStart, reasoning, text])
        #expect(events.contains(.thinking("pienso")))
        #expect(events.contains(.assistantText("OK")))
    }

    @Test func completedToolEmitsUseAndResult() {
        let events = run([stepStart, tool])
        #expect(events.contains(.toolUse(id: "c1", name: "read", summary: "/tmp/a.txt")))
        #expect(events.contains(.toolResult(toolUseId: "c1", isError: false, preview: "hola")))
    }

    @Test func rejectedToolBecomesErrorAndDenial() {
        let events = run([stepStart, toolError, text, stepFinish])
        #expect(events.contains(.toolResult(toolUseId: "c2", isError: true, preview: "The user rejected permission to use this specific tool call.")))
        #expect(events.contains(.denials([PermissionDenial(toolName: "bash", summary: "rm x")])))
    }

    @Test func exitZeroSynthesizesSuccessResultWithTotals() {
        let events = run([stepStart, text, stepFinish, stepFinish])
        guard case .result(let r)? = events.last else { Issue.record("no result"); return }
        #expect(!r.isError)
        #expect(r.text == "OK")
        #expect(r.sessionId == "ses_1")
        #expect(r.costUSD == 0.004)
        #expect(r.inputTokens == 200)
        #expect(r.outputTokens == 40)
        #expect(r.durationMs == 1000)
    }

    @Test func errorEventFailsWithoutSyntheticResult() {
        let line = #"{"type":"error","timestamp":1790979743038,"sessionID":"ses_x","error":{"name":"APIError","data":{"message":"Cannot connect to API","isRetryable":true}}}"#
        let events = run([line], exit: 1)
        #expect(events.contains(.error("Cannot connect to API")))
        #expect(!events.contains { if case .result = $0 { true } else { false } })
    }

    @Test func errorWithoutMessageFallsBackToName() {
        let events = run([#"{"type":"error","sessionID":"s","error":{"name":"UnknownError"}}"#], exit: 1)
        #expect(events.contains(.error("UnknownError")))
    }

    @Test func nonZeroExitWithoutErrorLeavesFailureToTheRunner() {
        #expect(!run([stepStart, text], exit: 2).contains { if case .result = $0 { true } else { false } })
    }

    @Test func toleratesGarbageAndUnknownTypes() {
        // Unknown types still carry a session id (so the run is initialized) but produce nothing else.
        #expect(run(["nope", "", "[]", #"{"type":"snapshot"}"#, #"{"type":"text"}"#, #"{"type":"tool_use","part":5}"#]).isEmpty)
        #expect(run([#"{"type":"snapshot","sessionID":"s"}"#], exit: 1) == [.initialized(sessionId: "s", model: nil)])
    }

    @Test func partialLinesAreBuffered() {
        var parser = OpenCodeEventParser()
        #expect(parser.feed(Data(text.prefix(20).utf8)).isEmpty)
        let events = parser.feed(Data((String(text.dropFirst(20)) + "\n").utf8))
        #expect(events.contains(.assistantText("OK")))
    }
}
