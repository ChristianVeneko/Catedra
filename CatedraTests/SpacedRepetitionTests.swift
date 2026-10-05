import Testing
import Foundation
@testable import Catedra

struct ReviewDayTests {
    @Test func caracasMidnightIsTheDayBoundary() {
        let before = Date(timeIntervalSince1970: 1_791_259_199) // 2026-10-06T03:59:59Z = 2026-10-05 23:59:59 Caracas
        let after = Date(timeIntervalSince1970: 1_791_259_200)  // 2026-10-06T04:00:00Z = 2026-10-06 00:00:00 Caracas
        #expect(ReviewDay(date: before).description == "2026-10-05")
        #expect(ReviewDay(date: after).description == "2026-10-06")
        #expect(ReviewDay(date: after).index == ReviewDay(date: before).index + 1)
    }

    @Test func stringRoundTripAndArithmetic() throws {
        let day = try #require(ReviewDay(string: "2026-02-27"))
        #expect(day.adding(days: 2).description == "2026-03-01")
        #expect(day.adding(days: 307).description == "2026-12-31")
        #expect(ReviewDay(string: "2028-02-29")?.adding(days: 1).description == "2028-03-01")
        #expect(ReviewDay(string: "1970-01-01")?.index == 0)
        #expect(ReviewDay(string: "nope") == nil)
        #expect(ReviewDay(string: "2026-13-01") == nil)
    }

    @Test func codableUsesTheString() throws {
        let day = try #require(ReviewDay(string: "2026-10-05"))
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-10-05"]"#)
        #expect(try JSONDecoder().decode([ReviewDay].self, from: data) == [day])
    }
}

struct SM2SchedulerTests {
    let today = ReviewDay(string: "2026-10-05")!

    func review(_ p: CardProgress?, _ g: ReviewGrade, on day: ReviewDay? = nil) -> CardProgress {
        SM2Scheduler.review(p, grade: g, today: day ?? today, fingerprint: "fp")
    }

    @Test func newCardGoodThenGoodGivesOneThenSixDays() {
        let first = review(nil, .good)
        #expect(first.interval == 1)
        #expect(first.repetitions == 1)
        #expect(first.due == today.adding(days: 1))
        #expect(first.firstReviewed == today)
        let second = review(first, .good, on: first.due)
        #expect(second.interval == 6)
        #expect(second.due == first.due.adding(days: 6))
        #expect(second.firstReviewed == today)
    }

    @Test func thirdGoodMultipliesByEase() {
        var p = review(nil, .good)
        p = review(p, .good, on: p.due)
        p = review(p, .good, on: p.due)
        #expect(p.interval == 15) // round(6 * 2.5)
        #expect(p.repetitions == 3)
        #expect(p.ease == 2.5)
    }

    @Test func easyAndHardAdjustEaseWithSM2Formula() {
        let easy = review(nil, .easy)
        #expect(abs(easy.ease - 2.6) < 1e-9)
        #expect(easy.interval == 4)
        let hard = review(nil, .hard)
        #expect(abs(hard.ease - 2.36) < 1e-9)
        #expect(hard.interval == 1)
    }

    @Test func easyBeatsGoodAndHardTrailsIt() {
        var base = review(nil, .good)
        base = review(base, .good, on: base.due) // interval 6, reps 2
        let good = review(base, .good, on: base.due)
        let easy = review(base, .easy, on: base.due)
        let hard = review(base, .hard, on: base.due)
        #expect(easy.interval > good.interval)
        #expect(hard.interval < good.interval)
        #expect(hard.interval > base.interval)
    }

    @Test func secondReviewIntervalsPerGrade() {
        let first = review(nil, .good)
        #expect(review(first, .hard, on: first.due).interval == 3)
        #expect(review(first, .good, on: first.due).interval == 6)
        #expect(review(first, .easy, on: first.due).interval == 10)
    }

    @Test func againOnLearnedCardIsALapse() {
        var p = review(nil, .good)
        p = review(p, .good, on: p.due)
        let lapsed = review(p, .again, on: p.due)
        #expect(lapsed.lapses == 1)
        #expect(lapsed.repetitions == 0)
        #expect(lapsed.interval == 1)
        #expect(abs(lapsed.ease - 2.3) < 1e-9)
        #expect(lapsed.due == p.due.adding(days: 1))
    }

    @Test func againOnNewCardIsNotALapse() {
        let p = review(nil, .again)
        #expect(p.lapses == 0)
        #expect(p.ease == 2.5)
        #expect(p.interval == 1)
        #expect(p.repetitions == 0)
        #expect(p.firstReviewed == today)
    }

    @Test func easeNeverDropsBelowFloor() {
        var p = review(nil, .good)
        for _ in 0..<30 { p = review(p, .hard, on: p.due) }
        #expect(p.ease == SM2Scheduler.minEase)
        for _ in 0..<30 { p = review(p, .again, on: p.due) }
        #expect(p.ease == SM2Scheduler.minEase)
        #expect(p.lapses == 1) // after the first lapse repetitions stay 0, so later failures are not new lapses
    }

    @Test func easeNeverExceedsCeiling() {
        var p = review(nil, .easy)
        for _ in 0..<30 { p = review(p, .easy, on: p.due) }
        #expect(p.ease == SM2Scheduler.maxEase)
    }

    @Test func intervalIsCapped() {
        var p = review(nil, .easy)
        for _ in 0..<30 { p = review(p, .easy, on: p.due) }
        #expect(p.interval == SM2Scheduler.maxInterval)
    }

    @Test func intervalAlwaysGrowsOnPass() {
        var p = review(nil, .good)
        p = review(p, .good, on: p.due)
        p.ease = SM2Scheduler.minEase
        let next = review(p, .good, on: p.due)
        #expect(next.interval > p.interval)
    }

    @Test func fingerprintIsStored() {
        #expect(review(nil, .good).fingerprint == "fp")
    }
}

struct GradeTests {
    @Test func spanishTitlesAndKeys() {
        #expect(ReviewGrade.allCases.map(\.title) == ["Otra vez", "Difícil", "Bien", "Fácil"])
        #expect(ReviewGrade.allCases.map(\.shortcut) == ["1", "2", "3", "4"])
        #expect(ReviewGrade(shortcut: "3") == .good)
        #expect(ReviewGrade(shortcut: "9") == nil)
    }
}
