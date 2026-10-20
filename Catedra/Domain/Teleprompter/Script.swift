import Foundation

/// A spoken script for the teleprompter: sections (`##` headings) split into sentences, with the spoken words
/// flattened in reading order so the aligner can track the speaker by word index.
struct Script: Equatable, Sendable {
    struct Word: Equatable, Sendable {
        /// As written, with punctuation (what the island shows).
        var text: String
        /// Lowercased, without accents or punctuation (what speech is matched against).
        var normalized: String
        var sentence: Int
    }

    enum Token: Equatable, Sendable {
        /// Index into `words`.
        case word(Int)
        /// Stage direction such as `[pausa]` or `[clic]`: shown as a chip, never expected in speech.
        case cue(String)
    }

    struct Sentence: Equatable, Sendable {
        var section: Int
        var tokens: [Token]
        /// Spoken words joined by spaces (cues left out).
        var text: String
    }

    struct Section: Equatable, Sendable {
        var title: String
        /// Indices into `sentences`.
        var sentences: Range<Int>
    }

    var title: String
    var language: String?
    var targetDuration: TimeInterval?
    var sections: [Section]
    var sentences: [Sentence]
    var words: [Word]

    var isEmpty: Bool { words.isEmpty }

    func estimatedDuration(wordsPerMinute: Double) -> TimeInterval {
        guard wordsPerMinute > 0 else { return 0 }
        return Double(words.count) / wordsPerMinute * 60
    }

    /// Sentence that contains the word at `index` (the last sentence once the script is finished).
    func sentenceIndex(forWord index: Int) -> Int {
        guard !words.isEmpty else { return 0 }
        return words[min(max(index, 0), words.count - 1)].sentence
    }

    /// First word of a sentence, or of the next sentence that has words.
    func firstWord(ofSentence index: Int) -> Int? {
        words.firstIndex { $0.sentence >= index }
    }
}

extension Script {
    /// Lowercase, accent-free, letters and digits only. Shared by the parser and the speech side of the aligner.
    static func normalize(_ word: String) -> String {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
