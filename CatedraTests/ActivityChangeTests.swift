import Testing
import Foundation
@testable import Catedra

struct ActivityChangeTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86400

    func tracked(_ id: String = "01/a", text: String? = "Hola", due: Date? = nil, opens: Date? = nil, cutoff: Date? = nil) -> TrackedActivity {
        TrackedActivity(id: id, name: "Tarea \(id)", courseName: "Control",
                        snapshot: ActivitySnapshot(text: text, due: due, opens: opens, cutoff: cutoff))
    }

    func baseline(_ items: [TrackedActivity]) -> ChangeTrackingState {
        ChangeDetector.process(state: nil, current: items, now: t0).state
    }

    @Test func firstRunOnlyTakesTheBaseline() {
        let result = ChangeDetector.process(state: nil, current: [tracked(text: "x")], now: t0)
        #expect(result.isBaseline)
        #expect(result.recorded.isEmpty)
        #expect(result.state.changes.isEmpty)
        #expect(result.state.snapshots["01/a"]?.text == "x")
    }

    @Test func unchangedActivityRecordsNothing() {
        let state = baseline([tracked()])
        let result = ChangeDetector.process(state: state, current: [tracked()], now: t0 + day)
        #expect(result.recorded.isEmpty)
        #expect(!result.isBaseline)
    }

    @Test func statementEditIsRecordedWithDiff() throws {
        let state = baseline([tracked(text: "a\nb")])
        let result = ChangeDetector.process(state: state, current: [tracked(text: "a\nc")], now: t0 + day)
        let change = try #require(result.recorded.first)
        #expect(change.textChanged)
        #expect(!change.datesChanged)
        #expect(change.diff.map(\.kind) == [.unchanged, .removed, .added])
        #expect(!change.seen)
        #expect(result.state.changes == [change])
    }

    @Test func dateChangeIsRecorded() throws {
        let state = baseline([tracked(due: t0)])
        let result = ChangeDetector.process(state: state, current: [tracked(due: t0 + 2 * day)], now: t0 + day)
        let change = try #require(result.recorded.first)
        #expect(!change.textChanged)
        #expect(change.dateChanges == [DateChange(field: .due, old: t0, new: t0 + 2 * day)])
    }

    @Test func newActivityGetsABaselineWithoutAlert() {
        let state = baseline([tracked("01/a")])
        let result = ChangeDetector.process(state: state, current: [tracked("01/a"), tracked("01/b", text: "nuevo")], now: t0 + day)
        #expect(result.recorded.isEmpty)
        #expect(result.state.snapshots["01/b"]?.text == "nuevo")
    }

    @Test func secondEditKeepsTheOriginalBeforeSnapshot() throws {
        var state = baseline([tracked(text: "v1")])
        state = ChangeDetector.process(state: state, current: [tracked(text: "v2")], now: t0 + day).state
        let result = ChangeDetector.process(state: state, current: [tracked(text: "v3")], now: t0 + 2 * day)
        let change = try #require(result.state.changes.first)
        #expect(result.state.changes.count == 1)
        #expect(change.before.text == "v1")
        #expect(change.after.text == "v3")
    }

    @Test func editedBackToWhatTheUserSawDropsTheChange() {
        var state = baseline([tracked(text: "v1")])
        state = ChangeDetector.process(state: state, current: [tracked(text: "v2")], now: t0 + day).state
        let result = ChangeDetector.process(state: state, current: [tracked(text: "v1")], now: t0 + 2 * day)
        #expect(result.state.changes.isEmpty)
        #expect(result.recorded.isEmpty)
    }

    @Test func markSeenKeepsRecordButClearsUnseen() {
        var state = baseline([tracked(text: "v1")])
        state = ChangeDetector.process(state: state, current: [tracked(text: "v2")], now: t0 + day).state
        state = ChangeDetector.markSeen("01/a", in: state)
        #expect(state.changes.first?.seen == true)
        // A later edit starts a fresh unseen change from the last seen snapshot.
        let result = ChangeDetector.process(state: state, current: [tracked(text: "v3")], now: t0 + 2 * day)
        #expect(result.recorded.first?.before.text == "v2")
        #expect(result.state.changes.filter { !$0.seen }.count == 1)
    }

    @Test func missingStatementFileDoesNotCountAsAChange() {
        let state = baseline([tracked(text: "v1")])
        let result = ChangeDetector.process(state: state, current: [tracked(text: nil)], now: t0 + day)
        #expect(result.recorded.isEmpty)
        #expect(result.state.snapshots["01/a"]?.text == "v1")
    }

    @Test func emptyReadKeepsTheState() {
        let state = baseline([tracked()])
        let result = ChangeDetector.process(state: state, current: [], now: t0 + day)
        #expect(result.state == state)
    }

    @Test func oldSeenChangesArePruned() {
        var state = baseline([tracked(text: "v1")])
        state = ChangeDetector.process(state: state, current: [tracked(text: "v2")], now: t0).state
        state = ChangeDetector.markSeen("01/a", in: state)
        let result = ChangeDetector.process(state: state, current: [tracked(text: "v2")], now: t0 + 31 * day)
        #expect(result.state.changes.isEmpty)
    }

    @Test func normalizerIgnoresStatusAttemptsAndDateLines() {
        let a = "# T\n\n- Estado: **Pendiente**\n- Entrega: 2026-10-01 10:00\n- Intentos realizados: 0\n\nTexto  \n"
        let b = "# T\n\n- Estado: **Entregada**\n- Entrega: 2026-10-09 10:00\n- Intentos realizados: 1\n\nTexto\n"
        #expect(StatementNormalizer.normalize(a) == StatementNormalizer.normalize(b))
        #expect(StatementNormalizer.normalize(a) != StatementNormalizer.normalize(b + "extra"))
    }

    @Test func notificationWording() throws {
        var state = baseline([tracked(text: "v1", due: t0)])
        let text = ChangeDetector.process(state: state, current: [tracked(text: "v2", due: t0)], now: t0).recorded
        #expect(ActivityChangeNotification.content(for: text)?.title == "Cátedra: cambió el enunciado")
        state = baseline([tracked(text: "v1", due: t0)])
        let date = ChangeDetector.process(state: state, current: [tracked(text: "v1", due: t0 + day)], now: t0).recorded
        #expect(ActivityChangeNotification.badges(for: try #require(date.first)) == ["Cambió la fecha"])
        let both = ChangeDetector.process(state: state, current: [tracked(text: "v2", due: t0 + day)], now: t0).recorded
        #expect(ActivityChangeNotification.badges(for: try #require(both.first)) == ["Cambió el enunciado", "Cambió la fecha"])
        #expect(ActivityChangeNotification.content(for: []) == nil)
        #expect(ActivityChangeNotification.content(for: text + both)?.title == "Cátedra: cambios en actividades")
    }
}
