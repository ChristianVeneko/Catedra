import Foundation

/// Tracks where the speaker is in a script from the recognizer's partial transcripts.
///
/// It compares the last few heard words with the script just ahead of `position`, tolerating misrecognitions
/// (small edit distance, partial words), and only ever moves forward. How far it may jump depends on how much matched:
/// one word only advances to the very next word, two words stay within `lookahead`, three or more may jump anywhere
/// ahead (the speaker skipped a part). Unrelated speech (improvising) leaves the position unchanged.
struct ScriptAligner: Equatable, Sendable {
    static let tailLength = 4
    static let lookahead = 12

    private let words: [String]
    /// Number of script words already spoken; the next expected word is `words[position]`.
    private(set) var position = 0

    init(script: Script) {
        words = script.words.map(\.normalized)
    }

    var wordCount: Int { words.count }
    var isFinished: Bool { position >= words.count }

    /// Feeds the recognizer's current transcript (it may be the whole utterance so far; only its tail is used).
    mutating func update(transcript: String) {
        let heard = transcript.split(whereSeparator: \.isWhitespace).map { Script.normalize(String($0)) }.filter { !$0.isEmpty }
        let tail = Array(heard.suffix(Self.tailLength))
        guard let last = tail.last, !isFinished else { return }

        var best: (end: Int, score: Int)?
        for end in (position + 1)...words.count where Self.matches(heard: last, expected: words[end - 1]) {
            let score = score(tail, endingAt: end)
            guard isAllowed(end: end, score: score) else { continue }
            if best == nil || score > best!.score { best = (end, score) }
        }
        if let best { position = best.end }
    }

    /// Manual move (previous / next sentence, section jumps), clamped to the script.
    mutating func jump(to wordIndex: Int) {
        position = min(max(wordIndex, 0), words.count)
    }

    // MARK: - Matching

    private func score(_ tail: [String], endingAt end: Int) -> Int {
        var score = 0
        for offset in 0..<tail.count {
            let index = end - 1 - offset
            guard index >= 0 else { break }
            if Self.matches(heard: tail[tail.count - 1 - offset], expected: words[index]) { score += 1 }
        }
        return score
    }

    private func isAllowed(end: Int, score: Int) -> Bool {
        switch score {
        case ..<1: false
        case 1: end == position + 1
        case 2: end <= position + Self.lookahead
        default: true
        }
    }

    static func matches(heard: String, expected: String) -> Bool {
        if heard == expected { return true }
        if heard.count >= 3, expected.hasPrefix(heard) { return true }
        let shorter = min(heard.count, expected.count)
        guard shorter >= 4 else { return false }
        return editDistance(heard, expected, limit: shorter >= 7 ? 2 : 1)
    }

    /// True when the Levenshtein distance is at most `limit`.
    private static func editDistance(_ a: String, _ b: String, limit: Int) -> Bool {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= limit else { return false }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count] <= limit
    }
}
