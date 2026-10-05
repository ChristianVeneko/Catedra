import Testing
import Foundation
@testable import Catedra

private final class RecordingNotifier: AgentNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(String, String)] = []
    var sent: [(String, String)] { lock.withLock { items } }
    func requestAuthorizationIfNeeded() async {}
    func notifyFinished(title: String, body: String) async { lock.withLock { items.append((title, body)) } }
}

private final class ScriptedRunner: AgentRunning, @unchecked Sendable {
    let events: [AgentEvent]
    private let lock = NSLock()
    private var started = 0
    var startCount: Int { lock.withLock { started } }
    init(_ events: [AgentEvent]) { self.events = events }
    func start(_ request: AgentRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        lock.withLock { started += 1 }
        return AsyncThrowingStream { c in
            for e in events { c.yield(e) }
            c.finish()
        }
    }
    func cancel(runID: UUID) {}
}

@MainActor
struct ChangeTrackingModelTests {
    func snapshot(_ activity: Activity) -> WorkspaceSnapshot {
        WorkspaceSnapshot(courses: [], activities: [activity], activitiesWithUserWork: [], lastSync: nil)
    }

    func write(_ text: String, root: URL, activity: Activity) throws {
        let dir = root.appendingPathComponent(activity.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: dir.appendingPathComponent("enunciado.md"), atomically: true, encoding: .utf8)
    }

    @Test func baselineDoesNotNotifyAndLaterEditDoes() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let activity = makeActivity(name: "Informe")
        let notifier = RecordingNotifier()
        let store = MemoryStateStore<ChangeTrackingState>()
        let model = ChangeTrackingModel(store: store, notifier: notifier, notificationsEnabled: { true })

        try write("# Informe\n\nEntregar en PDF", root: root, activity: activity)
        await model.process(snapshot: snapshot(activity), root: root)
        #expect(notifier.sent.isEmpty)
        #expect(model.change(for: activity.id) == nil)

        try write("# Informe\n\nEntregar en Word", root: root, activity: activity)
        await model.process(snapshot: snapshot(activity), root: root)
        #expect(notifier.sent.count == 1)
        let change = try #require(model.change(for: activity.id))
        #expect(change.textChanged)
        #expect(store.load()?.changes.count == 1)

        model.markSeen(activity.id)
        #expect(model.change(for: activity.id) == nil)
    }

    @Test func disabledToggleKeepsTheChangeButStaysSilent() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let activity = makeActivity(name: "Informe")
        let notifier = RecordingNotifier()
        let model = ChangeTrackingModel(store: MemoryStateStore<ChangeTrackingState>(), notifier: notifier, notificationsEnabled: { false })
        try write("uno", root: root, activity: activity)
        await model.process(snapshot: snapshot(activity), root: root)
        try write("dos", root: root, activity: activity)
        await model.process(snapshot: snapshot(activity), root: root)
        #expect(notifier.sent.isEmpty)
        #expect(model.change(for: activity.id) != nil)
    }
}

@MainActor
struct FocusTimerModelTests {
    @Test func tickingPastTheEndLogsTheSessionAndNotifiesOnce() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MemoryStateStore<[FocusSession]>()
        let notifier = RecordingNotifier()
        let model = FocusTimerModel(store: store, notifier: notifier, settings: { FocusSettings(focusMinutes: 25, breakMinutes: 5) },
                                    clock: { clock })
        model.start(activityID: "a", name: "Informe")
        #expect(model.remainingText == "25:00")
        clock.addTimeInterval(26 * 60)
        await model.tick()
        #expect(model.totalMinutes(for: "a") == 25)
        #expect(store.load()?.count == 1)
        #expect(model.phase == .rest)
        #expect(notifier.sent.count == 1)
        clock.addTimeInterval(10 * 60)
        await model.tick()
        #expect(!model.isRunning)
        #expect(notifier.sent.count == 2)
    }

    @Test func stopLogsElapsedMinutes() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let model = FocusTimerModel(store: MemoryStateStore<[FocusSession]>(), clock: { clock })
        model.start(activityID: "a", name: "Informe")
        clock.addTimeInterval(7 * 60)
        model.stop()
        #expect(model.totalMinutes(for: "a") == 7)
        #expect(!model.isRunning)
    }
}

@MainActor
struct WeeklySummaryModelTests {
    let monday = ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")!

    fileprivate func model(runner: AgentRunning, agent: Bool, enabled: Bool = true, dir: URL, notifier: RecordingNotifier = RecordingNotifier())
        -> WeeklySummaryModel {
        let m = WeeklySummaryModel(store: MemoryStateStore<WeeklySummaryState>(), runner: runner, directory: dir, notifier: notifier)
        m.isEnabled = { enabled }
        m.agent = { agent ? (.claude, "/fake/claude", AgentOptions()) : nil }
        return m
    }

    func waitUntilIdle(_ m: WeeklySummaryModel) async {
        for _ in 0..<200 where m.isGenerating { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func withoutAgentTheLocalDigestIsShownAndNoRunStarts() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ScriptedRunner([])
        let m = model(runner: runner, agent: false, dir: dir)
        m.checkIfDue(now: monday)
        await waitUntilIdle(m)
        #expect(runner.startCount == 0)
        let card = try #require(m.card(now: monday))
        #expect(!card.usedAgent)
        #expect(card.text.contains("# Semana 2026-W41"))
        #expect(m.state.lastWeekKey == "2026-W41")
    }

    @Test func agentResultTextBecomesTheSummary() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = AgentResult(isError: false, subtype: "success", text: "Resumen escrito por el agente", sessionId: nil,
                                 costUSD: nil, durationMs: nil)
        let runner = ScriptedRunner([.result(result)])
        let m = model(runner: runner, agent: true, dir: dir)
        m.checkIfDue(now: monday)
        await waitUntilIdle(m)
        #expect(runner.startCount == 1)
        let card = try #require(m.card(now: monday))
        #expect(card.usedAgent)
        #expect(card.text == "Resumen escrito por el agente")
    }

    @Test func disabledSettingNeverRunsAndOnlyOncePerWeek() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ScriptedRunner([])
        let off = model(runner: runner, agent: true, enabled: false, dir: dir)
        off.checkIfDue(now: monday)
        #expect(runner.startCount == 0)
        #expect(!off.isGenerating)

        let on = model(runner: runner, agent: false, dir: dir)
        on.checkIfDue(now: monday)
        await waitUntilIdle(on)
        let first = on.state.latest?.generatedAt
        on.checkIfDue(now: monday.addingTimeInterval(3600))
        #expect(on.state.latest?.generatedAt == first)
    }

    @Test func dismissHidesTheCardForTheWeek() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let m = model(runner: ScriptedRunner([]), agent: false, dir: dir)
        m.generate(now: monday)
        await waitUntilIdle(m)
        #expect(m.card(now: monday) != nil)
        m.dismiss(now: monday)
        #expect(m.card(now: monday) == nil)
    }
}
