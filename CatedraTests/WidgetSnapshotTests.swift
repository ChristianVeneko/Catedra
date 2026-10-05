import Testing
import Foundation
@testable import Catedra

struct WidgetSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func candidate(_ name: String, due: TimeInterval?, submitted: Bool = false, course: String = "Control", hex: String = "#5B6BF5")
        -> WidgetSnapshotBuilder.Candidate {
        .init(id: "c/\(name)", name: name, courseName: course, due: due.map { now.addingTimeInterval($0) }, isSubmitted: submitted, colorHex: hex)
    }

    // MARK: Builder

    @Test func keepsTheThreeSoonestUpcomingDeliveries() {
        let snapshot = WidgetSnapshotBuilder.build(
            now: now,
            candidates: [candidate("d", due: 4000), candidate("a", due: 1000), candidate("c", due: 3000), candidate("b", due: 2000)],
            cardsDue: 0, focus: nil)
        #expect(snapshot.deliveries.map(\.name) == ["a", "b", "c"])
    }

    @Test func excludesSubmittedOverdueAndUndated() {
        let snapshot = WidgetSnapshotBuilder.build(
            now: now,
            candidates: [candidate("done", due: 1000, submitted: true), candidate("late", due: -60), candidate("none", due: nil),
                         candidate("ok", due: 500)],
            cardsDue: 0, focus: nil)
        #expect(snapshot.deliveries.map(\.name) == ["ok"])
    }

    @Test func dueExactlyNowCountsAsOverdue() {
        let snapshot = WidgetSnapshotBuilder.build(now: now, candidates: [candidate("edge", due: 0)], cardsDue: 0, focus: nil)
        #expect(snapshot.deliveries.isEmpty)
    }

    @Test func carriesFieldsAndClampsNegativeCards() {
        let snapshot = WidgetSnapshotBuilder.build(
            now: now, candidates: [candidate("a", due: 60, course: "Redes", hex: "#112233")], cardsDue: -4, focus: nil)
        #expect(snapshot.generatedAt == now)
        #expect(snapshot.cardsDue == 0)
        #expect(snapshot.deliveries.first == .init(id: "c/a", name: "a", courseName: "Redes", due: now.addingTimeInterval(60), colorHex: "#112233"))
    }

    @Test func sameDueDateKeepsInputOrder() {
        let snapshot = WidgetSnapshotBuilder.build(
            now: now, candidates: [candidate("x", due: 60), candidate("y", due: 60)], cardsDue: 0, focus: nil)
        #expect(snapshot.deliveries.map(\.name) == ["x", "y"])
    }

    // MARK: Encoding

    @Test func roundTripsThroughJSON() throws {
        let original = WidgetSnapshotBuilder.build(
            now: now, candidates: [candidate("a", due: 60)], cardsDue: 7,
            focus: .init(activityName: "Tarea 1", endsAt: now.addingTimeInterval(900)))
        let decoded = try WidgetSnapshot.decode(original.encoded())
        #expect(decoded == original)
    }

    @Test func decodingGarbageThrows() {
        #expect(throws: (any Error).self) { try WidgetSnapshot.decode(Data("nope".utf8)) }
    }

    // MARK: Time-dependent views

    @Test func deliveriesAtDropsThoseAlreadyDue() {
        let snapshot = WidgetSnapshotBuilder.build(now: now, candidates: [candidate("a", due: 100), candidate("b", due: 200)], cardsDue: 0, focus: nil)
        #expect(snapshot.deliveries(at: now.addingTimeInterval(150)).map(\.name) == ["b"])
    }

    @Test func focusAtHidesAnEndedSession() {
        let snapshot = WidgetSnapshotBuilder.build(now: now, candidates: [], cardsDue: 0, focus: .init(activityName: "T", endsAt: now.addingTimeInterval(60)))
        #expect(snapshot.focus(at: now) != nil)
        #expect(snapshot.focus(at: now.addingTimeInterval(60)) == nil)
    }

    @Test func staleAfterTwentyFourHours() {
        let snapshot = WidgetSnapshotBuilder.build(now: now, candidates: [], cardsDue: 0, focus: nil)
        #expect(!snapshot.isStale(at: now.addingTimeInterval(23 * 3600)))
        #expect(snapshot.isStale(at: now.addingTimeInterval(24 * 3600 + 1)))
    }

    @Test func sameContentIgnoresGenerationTime() {
        let a = WidgetSnapshotBuilder.build(now: now, candidates: [candidate("a", due: 60)], cardsDue: 1, focus: nil)
        let b = WidgetSnapshotBuilder.build(now: now.addingTimeInterval(5), candidates: [candidate("a", due: 60)], cardsDue: 1, focus: nil)
        let c = WidgetSnapshotBuilder.build(now: now, candidates: [candidate("a", due: 60)], cardsDue: 2, focus: nil)
        #expect(a.hasSameContent(as: b))
        #expect(!a.hasSameContent(as: c))
    }

    // MARK: Timeline

    @Test func timelineHasHalfHourStepsAndDueTimes() {
        let snapshot = WidgetSnapshotBuilder.build(
            now: now, candidates: [candidate("a", due: 10 * 60)], cardsDue: 0, focus: nil)
        let dates = WidgetTimelinePlanner.entryDates(now: now, snapshot: snapshot, horizon: 3600)
        #expect(dates == [now, now.addingTimeInterval(600), now.addingTimeInterval(1800), now.addingTimeInterval(3600)])
    }

    @Test func timelineIncludesFocusEndAndIgnoresPastOrBeyondHorizon() {
        let snapshot = WidgetSnapshotBuilder.build(
            now: now, candidates: [candidate("far", due: 9 * 3600)], cardsDue: 0,
            focus: .init(activityName: "T", endsAt: now.addingTimeInterval(1200)))
        let dates = WidgetTimelinePlanner.entryDates(now: now, snapshot: snapshot, horizon: 3600)
        #expect(dates == [now, now.addingTimeInterval(1200), now.addingTimeInterval(1800), now.addingTimeInterval(3600)])
    }

    // MARK: Links

    @Test func linkRoundTrips() {
        let id = "08 - Teoria de Control II/Tarea #1?x"
        #expect(WidgetLink.parse(WidgetLink.activity(id).url) == .activity(id))
        #expect(WidgetLink.parse(WidgetLink.review.url) == .review)
        #expect(WidgetLink.parse(WidgetLink.open.url) == .open)
    }

    @Test func linkRejectsForeignURLs() {
        #expect(WidgetLink.parse(URL(string: "https://example.com")!) == nil)
        #expect(WidgetLink.parse(URL(string: "catedra://unknown")!) == nil)
        #expect(WidgetLink.parse(URL(string: "catedra://activity")!) == nil)
    }

    // MARK: Store

    @Test func storeWritesAndReadsBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)
        #expect(store.read() == nil)
        let snapshot = WidgetSnapshotBuilder.build(now: now, candidates: [candidate("a", due: 60)], cardsDue: 3, focus: nil)
        try store.write(snapshot)
        #expect(store.read() == snapshot)
    }

    @Test func storeReadsNilOnCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: dir.appendingPathComponent(WidgetSnapshotStore.fileName))
        #expect(WidgetSnapshotStore(directory: dir).read() == nil)
    }

    // MARK: Throttle

    @Test func throttleAllowsFirstThenWaits() {
        var throttle = WidgetReloadThrottle(minimumInterval: 30)
        let first = throttle.shouldReload(now: now)
        let tooSoon = throttle.shouldReload(now: now.addingTimeInterval(10))
        let later = throttle.shouldReload(now: now.addingTimeInterval(31))
        #expect(first)
        #expect(!tooSoon)
        #expect(later)
    }

    // MARK: Course colors

    @Test func courseHexFollowsTheAppPalette() {
        #expect(WidgetCourseColor.hex(forCourseNumber: 1) == WidgetCourseColor.hexes[0])
        #expect(WidgetCourseColor.hex(forCourseNumber: 10) == WidgetCourseColor.hexes[0])
        #expect(WidgetCourseColor.hex(forCourseNumber: 0) == WidgetCourseColor.hexes[8])
    }
}

@MainActor
struct WidgetSyncModelTests {
    @Test func writesOnlyWhenContentChangesAndThrottlesReloads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        var cards = 1
        var reloads = 0
        let model = WidgetSyncModel(store: WidgetSnapshotStore(directory: dir), clock: { now }, reload: { reloads += 1 }) {
            WidgetSnapshotBuilder.build(now: $0, candidates: [], cardsDue: cards, focus: nil)
        }
        model.refresh()
        #expect(reloads == 1)
        #expect(WidgetSnapshotStore(directory: dir).read()?.cardsDue == 1)

        now.addTimeInterval(5)
        model.refresh() // same content: nothing to do
        #expect(reloads == 1)

        cards = 2
        now.addTimeInterval(5)
        model.refresh() // changed but inside the throttle window: file updated, reload deferred
        #expect(WidgetSnapshotStore(directory: dir).read()?.cardsDue == 2)
        #expect(reloads == 1)
    }
}
