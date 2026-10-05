import Foundation

enum ReviewGrade: Int, CaseIterable, Codable, Sendable {
    case again = 1, hard, good, easy

    var title: String {
        switch self {
        case .again: "Otra vez"
        case .hard: "Difícil"
        case .good: "Bien"
        case .easy: "Fácil"
        }
    }

    /// Keyboard shortcut in the review session: 1 to 4.
    var shortcut: String { String(rawValue) }

    init?(shortcut: String) {
        guard let value = Int(shortcut), let grade = ReviewGrade(rawValue: value) else { return nil }
        self = grade
    }
}

/// Scheduling state of one card. Stored per course and card id.
struct CardProgress: Equatable, Codable, Sendable {
    var ease: Double
    /// Days between the last review and `due`.
    var interval: Int
    /// Consecutive passing reviews; reset by "Otra vez".
    var repetitions: Int
    var lapses: Int
    var due: ReviewDay
    var firstReviewed: ReviewDay
    var lastReviewed: ReviewDay
    /// `Flashcard.fingerprint` of the question when last reviewed; lets progress follow a card whose id changed.
    var fingerprint: String
}

/// SM-2 (SuperMemo 2) with four grades.
///
/// Grades map to SM-2 qualities: Difícil = 3, Bien = 4, Fácil = 5 (all passes) and Otra vez = fail. The ease factor
/// follows the original formula `EF' = EF + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)`, bounded to 1.3...3.0.
/// Deliberate refinements over the original: a fail only lowers the ease (-0.2) when the card was already learned
/// (a lapse), a fail schedules the card for the next day, Difícil grows the interval slowly (x1.2) and Fácil adds a
/// 1.3 bonus, and intervals are capped at one year.
enum SM2Scheduler {
    static let defaultEase = 2.5
    static let minEase = 1.3
    static let maxEase = 3.0
    static let maxInterval = 365
    static let lapsePenalty = 0.2
    static let hardMultiplier = 1.2
    static let easyBonus = 1.3

    static func review(_ previous: CardProgress?, grade: ReviewGrade, today: ReviewDay, fingerprint: String) -> CardProgress {
        let ease = previous?.ease ?? defaultEase
        let interval = previous?.interval ?? 0
        let repetitions = previous?.repetitions ?? 0
        var lapses = previous?.lapses ?? 0

        var newEase = ease
        var newInterval: Int
        var newRepetitions = repetitions + 1

        switch grade {
        case .again:
            if repetitions > 0 {
                lapses += 1
                newEase = ease - lapsePenalty
            }
            newRepetitions = 0
            newInterval = 1
        case .hard:
            newEase = ease + easeDelta(quality: 3)
            switch repetitions {
            case 0: newInterval = 1
            case 1: newInterval = 3
            default: newInterval = max(interval + 1, Int((Double(interval) * hardMultiplier).rounded()))
            }
        case .good:
            newEase = ease + easeDelta(quality: 4)
            switch repetitions {
            case 0: newInterval = 1
            case 1: newInterval = 6
            default: newInterval = max(interval + 1, Int((Double(interval) * clamp(newEase)).rounded()))
            }
        case .easy:
            newEase = ease + easeDelta(quality: 5)
            switch repetitions {
            case 0: newInterval = 4
            case 1: newInterval = 10
            default: newInterval = max(interval + 1, Int((Double(interval) * clamp(newEase) * easyBonus).rounded()))
            }
        }

        newInterval = min(max(newInterval, 1), maxInterval)
        return CardProgress(
            ease: clamp(newEase), interval: newInterval, repetitions: newRepetitions, lapses: lapses,
            due: today.adding(days: newInterval), firstReviewed: previous?.firstReviewed ?? today, lastReviewed: today,
            fingerprint: fingerprint)
    }

    private static func easeDelta(quality q: Int) -> Double {
        let d = Double(5 - q)
        return 0.1 - d * (0.08 + d * 0.02)
    }

    private static func clamp(_ ease: Double) -> Double { min(max(ease, minEase), maxEase) }
}
