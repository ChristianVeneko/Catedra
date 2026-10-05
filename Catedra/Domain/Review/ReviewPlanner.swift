import Foundation

struct DeckCounts: Equatable, Sendable {
    /// Learned cards due today or overdue.
    var due: Int
    /// Never-reviewed cards the daily limit still allows today.
    var new: Int
    /// Cards in the deck.
    var total: Int

    /// What the "Tarjetas para hoy" counter shows.
    var today: Int { due + new }
}

/// Pure queue and bookkeeping rules for the review of one deck (one course).
enum ReviewPlanner {
    /// Cards to study today: due cards oldest first, then new cards in file order up to the remaining daily allowance.
    static func queue(cards: [Flashcard], progress: [String: CardProgress], today: ReviewDay, newLimit: Int) -> [Flashcard] {
        let order = Dictionary(cards.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let due = cards.compactMap { card -> (Flashcard, ReviewDay)? in
            guard let p = progress[card.id], p.due <= today else { return nil }
            return (card, p.due)
        }
        .sorted { ($0.1, order[$0.0.id] ?? 0) < ($1.1, order[$1.0.id] ?? 0) }
        .map(\.0)
        let allowance = max(0, newLimit - introducedToday(progress: progress, today: today))
        let fresh = cards.filter { progress[$0.id] == nil }.prefix(allowance)
        return due + fresh
    }

    static func counts(cards: [Flashcard], progress: [String: CardProgress], today: ReviewDay, newLimit: Int) -> DeckCounts {
        let due = cards.filter { progress[$0.id].map { $0.due <= today } ?? false }.count
        let newCount = cards.filter { progress[$0.id] == nil }.count
        let allowance = max(0, newLimit - introducedToday(progress: progress, today: today))
        return DeckCounts(due: due, new: min(newCount, allowance), total: cards.count)
    }

    /// Cards whose first review happened today (orphans included: the limit is about today's effort).
    static func introducedToday(progress: [String: CardProgress], today: ReviewDay) -> Int {
        progress.values.filter { $0.firstReviewed == today }.count
    }

    /// Keeps progress for the cards of the current file and for cards that disappeared (they may come back, and the
    /// user's history is never dropped silently). The one change: a card with no progress inherits the progress of an
    /// orphan with the same question when an agent re-wrote the file with a different id.
    static func reconcile(cards: [Flashcard], progress: [String: CardProgress]) -> [String: CardProgress] {
        let present = Set(cards.map(\.id))
        var orphansByFingerprint: [String: [String]] = [:]
        for (id, p) in progress where !present.contains(id) {
            orphansByFingerprint[p.fingerprint, default: []].append(id)
        }
        guard !orphansByFingerprint.isEmpty else { return progress }
        var result = progress
        for card in cards where result[card.id] == nil {
            guard var candidates = orphansByFingerprint[card.fingerprint], !candidates.isEmpty else { continue }
            candidates.sort()
            let orphan = candidates.removeFirst()
            orphansByFingerprint[card.fingerprint] = candidates
            result[card.id] = result.removeValue(forKey: orphan)
        }
        return result
    }
}

/// One study session: a fixed queue where "Otra vez" brings the card back once at the end.
struct ReviewSession: Equatable, Sendable {
    struct Outcome: Equatable, Sendable {
        let card: Flashcard
        let grade: ReviewGrade
        /// False for the second pass of a card graded "Otra vez": it does not reschedule the card again.
        let recordsProgress: Bool
    }

    private struct Entry: Equatable, Sendable {
        let card: Flashcard
        let isRetry: Bool
    }

    private var entries: [Entry]
    let total: Int
    private(set) var reviewedCount = 0
    private(set) var tally: [ReviewGrade: Int] = [:]

    init(cards: [Flashcard]) {
        entries = cards.map { Entry(card: $0, isRetry: false) }
        total = cards.count
    }

    var current: Flashcard? { entries.first?.card }
    var isFinished: Bool { entries.isEmpty }
    var remaining: Int { entries.count }
    var fractionCompleted: Double { total == 0 ? 1 : Double(reviewedCount) / Double(total) }

    @discardableResult
    mutating func grade(_ grade: ReviewGrade) -> Outcome? {
        guard !entries.isEmpty else { return nil }
        let entry = entries.removeFirst()
        if !entry.isRetry {
            tally[grade, default: 0] += 1
            reviewedCount += 1
            if grade == .again { entries.append(Entry(card: entry.card, isRetry: true)) }
        }
        return Outcome(card: entry.card, grade: grade, recordsProgress: !entry.isRetry)
    }
}

enum ReviewSummary {
    static func todayText(_ count: Int) -> String {
        switch count {
        case 0: "Sin tarjetas para hoy"
        case 1: "1 tarjeta para hoy"
        default: "\(count) tarjetas para hoy"
        }
    }
}
