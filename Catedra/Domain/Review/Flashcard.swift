import Foundation

struct Flashcard: Identifiable, Equatable, Sendable {
    let id: String
    let question: String
    let answer: String
    /// File the card was derived from, relative to the course folder.
    let source: String?
    let tags: [String]

    var fingerprint: String { Self.fingerprint(of: question) }

    /// Stable hash of a question ignoring case, accents and spacing (FNV-1a, 64 bit, hex).
    static func fingerprint(of question: String) -> String {
        let folded = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let normalized = folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

struct FlashcardDeck: Equatable, Sendable {
    let generatedAt: Date?
    let cards: [Flashcard]
}

enum FlashcardError: Error, Equatable, Sendable {
    case notJSON
    case notAnObject
}

extension FlashcardError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notJSON: "El archivo de tarjetas no es un JSON válido."
        case .notAnObject: "El archivo de tarjetas no tiene el formato esperado."
        }
    }
}

/// Tolerant reader of `apuntes/tarjetas.json`: a top-level object with `cards`, or a bare array. Cards without a
/// question or an answer are skipped; a missing id is derived from the question so it stays stable between runs.
enum FlashcardParser {
    static func parse(_ data: Data) throws -> FlashcardDeck {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { throw FlashcardError.notJSON }
        let entries: [Any]
        var generatedAt: Date?
        if let root = object as? [String: Any] {
            entries = root["cards"] as? [Any] ?? []
            generatedAt = JSONText.string(root["generatedAt"]).flatMap(JSONText.date)
        } else if let array = object as? [Any] {
            entries = array
        } else {
            throw FlashcardError.notAnObject
        }

        var cards: [Flashcard] = []
        var seen: [String: Int] = [:]
        for entry in entries {
            guard let dict = entry as? [String: Any], let question = JSONText.string(dict["question"]),
                  let answer = JSONText.string(dict["answer"]) else { continue }
            let base = JSONText.identifier(dict["id"]) ?? "card-" + Flashcard.fingerprint(of: question)
            let occurrence = (seen[base] ?? 0) + 1
            seen[base] = occurrence
            cards.append(Flashcard(id: occurrence == 1 ? base : "\(base)-\(occurrence)", question: question, answer: answer,
                                   source: JSONText.string(dict["source"]), tags: JSONText.strings(dict["tags"])))
        }
        return FlashcardDeck(generatedAt: generatedAt, cards: cards)
    }
}

enum FlashcardLoadState: Equatable, Sendable {
    case missing
    case loaded(FlashcardDeck)
    case invalid(String)
}

enum FlashcardFile {
    /// Inside the course's `apuntes/`: the folder agents may write to and the sync never touches.
    static let relativePath = "apuntes/tarjetas.json"

    static func load(in courseFolder: URL) -> FlashcardLoadState {
        guard let data = try? Data(contentsOf: courseFolder.appendingPathComponent(relativePath)) else { return .missing }
        do { return .loaded(try FlashcardParser.parse(data)) } catch { return .invalid(error.localizedDescription) }
    }
}

/// Small helpers shared by the tolerant JSON readers.
enum JSONText {
    static func string(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// A string or an integer, as text.
    static func identifier(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }

    static func strings(_ value: Any?) -> [String] {
        if let text = string(value) { return [text] }
        return (value as? [Any])?.compactMap { string($0) } ?? []
    }

    static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return plain.date(from: text) ?? fractional.date(from: text) ?? dateOnly.date(from: text)
    }
}
