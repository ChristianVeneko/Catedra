import Testing
import Foundation
@testable import Catedra

struct ReviewPlannerTests {
    let today = ReviewDay(string: "2026-10-05")!

    func card(_ id: String, _ question: String? = nil) -> Flashcard {
        Flashcard(id: id, question: question ?? "Pregunta \(id)", answer: "r", source: nil, tags: [])
    }

    func progress(for card: Flashcard, due: String, first: String = "2026-09-01", interval: Int = 6) -> CardProgress {
        CardProgress(ease: 2.5, interval: interval, repetitions: 2, lapses: 0, due: ReviewDay(string: due)!,
                     firstReviewed: ReviewDay(string: first)!, lastReviewed: ReviewDay(string: first)!,
                     fingerprint: card.fingerprint)
    }

    @Test func dueCardsComeFirstOldestFirstThenNew() {
        let a = card("a"), b = card("b"), c = card("c"), d = card("d"), future = card("f")
        let state = [
            "a": progress(for: a, due: "2026-10-05"), "b": progress(for: b, due: "2026-10-01"),
            "f": progress(for: future, due: "2026-10-06"),
        ]
        let queue = ReviewPlanner.queue(cards: [a, c, b, future, d], progress: state, today: today, newLimit: 20)
        #expect(queue.map(\.id) == ["b", "a", "c", "d"])
    }

    @Test func newCardLimitCapsIntroductions() {
        let cards = (1...5).map { card("n\($0)") }
        let queue = ReviewPlanner.queue(cards: cards, progress: [:], today: today, newLimit: 3)
        #expect(queue.map(\.id) == ["n1", "n2", "n3"])
        #expect(ReviewPlanner.queue(cards: cards, progress: [:], today: today, newLimit: 0).isEmpty)
    }

    @Test func cardsAlreadyIntroducedTodayConsumeTheLimit() {
        let intro = card("i1"), intro2 = card("i2")
        let new = (1...5).map { card("n\($0)") }
        var state: [String: CardProgress] = [:]
        // Introduced today, due tomorrow: not in the queue, but they count against the daily limit.
        state["i1"] = progress(for: intro, due: "2026-10-06", first: "2026-10-05", interval: 1)
        state["i2"] = progress(for: intro2, due: "2026-10-06", first: "2026-10-05", interval: 1)
        let queue = ReviewPlanner.queue(cards: [intro, intro2] + new, progress: state, today: today, newLimit: 3)
        #expect(queue.map(\.id) == ["n1"])
        #expect(ReviewPlanner.introducedToday(progress: state, today: today) == 2)
    }

    @Test func countsMatchQueue() {
        let a = card("a"), b = card("b")
        let new = (1...30).map { card("n\($0)") }
        let state = ["a": progress(for: a, due: "2026-10-04"), "b": progress(for: b, due: "2026-11-01")]
        let counts = ReviewPlanner.counts(cards: [a, b] + new, progress: state, today: today, newLimit: 20)
        #expect(counts == DeckCounts(due: 1, new: 20, total: 32))
        #expect(counts.today == 21)
    }

    @Test func deletedCardsKeepProgressButLeaveTheQueue() {
        let kept = card("kept"), gone = card("gone")
        let state = ["kept": progress(for: kept, due: "2026-10-05"), "gone": progress(for: gone, due: "2026-10-05")]
        let result = ReviewPlanner.reconcile(cards: [kept], progress: state)
        #expect(result["gone"] != nil)
        #expect(ReviewPlanner.queue(cards: [kept], progress: result, today: today, newLimit: 20).map(\.id) == ["kept"])
        #expect(ReviewPlanner.counts(cards: [kept], progress: result, today: today, newLimit: 20).due == 1)
        // Restoring the card brings its progress back.
        #expect(ReviewPlanner.queue(cards: [kept, gone], progress: result, today: today, newLimit: 20).map(\.id) == ["kept", "gone"])
    }

    @Test func reconcileMigratesProgressWhenAnAgentChangesAnId() {
        let old = card("old-id", "¿Qué es un nodo?")
        let renamed = card("new-id", "¿que es un nodo?")
        let state = ["old-id": progress(for: old, due: "2026-10-20")]
        let result = ReviewPlanner.reconcile(cards: [renamed], progress: state)
        #expect(result["new-id"]?.due == ReviewDay(string: "2026-10-20"))
        #expect(result["old-id"] == nil)
    }

    @Test func reconcileNeverOverwritesExistingProgress() {
        let a = card("a", "misma"), b = card("b", "misma")
        let state = ["a": progress(for: a, due: "2026-10-20"), "b": progress(for: b, due: "2026-11-20")]
        let result = ReviewPlanner.reconcile(cards: [a, b], progress: state)
        #expect(result == state)
    }

    @Test func reconcileDoesNotStealProgressOfACardStillPresent() {
        let a = card("a", "misma"), b = card("b", "misma")
        let state = ["a": progress(for: a, due: "2026-10-20")]
        let result = ReviewPlanner.reconcile(cards: [a, b], progress: state)
        #expect(result["a"] != nil)
        #expect(result["b"] == nil)
    }

    @Test func mergingNewCardsKeepsExistingProgress() {
        let a = card("a")
        let state = ["a": progress(for: a, due: "2026-10-20")]
        let merged = ReviewPlanner.reconcile(cards: [a, card("b"), card("c")], progress: state)
        #expect(merged == state)
        let queue = ReviewPlanner.queue(cards: [a, card("b"), card("c")], progress: merged, today: today, newLimit: 20)
        #expect(queue.map(\.id) == ["b", "c"])
    }
}

struct ReviewSessionTests {
    func cards(_ n: Int) -> [Flashcard] {
        (1...n).map { Flashcard(id: "c\($0)", question: "q\($0)", answer: "a", source: nil, tags: []) }
    }

    @Test func advancesAndTracksProgress() {
        var session = ReviewSession(cards: cards(2))
        #expect(session.current?.id == "c1")
        #expect(session.fractionCompleted == 0)
        let first = session.grade(.good)
        #expect(first?.card.id == "c1")
        #expect(first?.recordsProgress == true)
        #expect(session.current?.id == "c2")
        #expect(session.fractionCompleted == 0.5)
        _ = session.grade(.easy)
        #expect(session.isFinished)
        #expect(session.fractionCompleted == 1)
        #expect(session.tally[.good] == 1 && session.tally[.easy] == 1)
    }

    @Test func againRequeuesOnceWithoutRecordingTheRetry() {
        var session = ReviewSession(cards: cards(2))
        _ = session.grade(.again)
        #expect(session.current?.id == "c2")
        #expect(session.remaining == 2)
        _ = session.grade(.good)
        #expect(session.current?.id == "c1")
        let retry = session.grade(.again)
        #expect(retry?.recordsProgress == false)
        #expect(session.isFinished)
        #expect(session.reviewedCount == 2)
    }

    @Test func gradingAnEmptySessionDoesNothing() {
        var session = ReviewSession(cards: [])
        #expect(session.isFinished)
        #expect(session.grade(.good) == nil)
        #expect(session.fractionCompleted == 1)
    }
}

struct ReviewProgressFileTests {
    @Test func roundTripsAndToleratesBadEntries() throws {
        var file = ReviewProgressFile()
        file.settings.newCardsPerDay = 12
        let progress = CardProgress(ease: 2.4, interval: 6, repetitions: 2, lapses: 1, due: ReviewDay(string: "2026-10-11")!,
                                    firstReviewed: ReviewDay(string: "2026-10-01")!, lastReviewed: ReviewDay(string: "2026-10-05")!,
                                    fingerprint: "abc")
        file.courses["01 - Algebra"] = ["c1": progress]
        let data = try JSONEncoder().encode(file)
        #expect(try JSONDecoder().decode(ReviewProgressFile.self, from: data) == file)

        let dirty = Data(#"{"settings":{"newCardsPerDay":"x"},"courses":{"A":{"ok":{"ease":2.5,"interval":1,"repetitions":1,"lapses":0,"due":"2026-10-06","firstReviewed":"2026-10-05","lastReviewed":"2026-10-05","fingerprint":"f"},"bad":{"ease":"x"}},"B":7}}"#.utf8)
        let decoded = try JSONDecoder().decode(ReviewProgressFile.self, from: dirty)
        #expect(decoded.settings.newCardsPerDay == ReviewSettings.defaultNewCardsPerDay)
        #expect(decoded.courses["A"]?.keys.sorted() == ["ok"])
        #expect(decoded.courses["B"] == nil)
    }

    @Test func newCardLimitIsClamped() {
        var settings = ReviewSettings()
        settings.newCardsPerDay = 9999
        #expect(settings.clampedNewCardsPerDay == ReviewSettings.maxNewCardsPerDay)
        settings.newCardsPerDay = -3
        #expect(settings.clampedNewCardsPerDay == 0)
        #expect(ReviewSettings().newCardsPerDay == 20)
    }

    @Test func todayTextIsSpanish() {
        #expect(ReviewSummary.todayText(0) == "Sin tarjetas para hoy")
        #expect(ReviewSummary.todayText(1) == "1 tarjeta para hoy")
        #expect(ReviewSummary.todayText(12) == "12 tarjetas para hoy")
    }

    @Test func storeRoundTripsOnDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("rp-\(UUID().uuidString)/review-progress.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = JSONReviewProgressStore(file: file)
        #expect(store.load() == ReviewProgressFile())
        var data = ReviewProgressFile()
        data.settings.newCardsPerDay = 5
        try store.save(data)
        #expect(store.load() == data)
    }
}
