import Foundation

struct QuizQuestion: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case multipleChoice, shortAnswer }

    let id: String
    let kind: Kind
    let prompt: String
    let options: [String]
    /// Index in `options` of the correct one, when it could be resolved.
    let correctIndex: Int?
    /// Reference answer (the correct option text, or the model answer of a short question).
    let answer: String
    let explanation: String?
    let source: String?

    /// Multiple choice whose correct option is known: the app corrects it without asking the student.
    var isAutoGradable: Bool { kind == .multipleChoice && correctIndex != nil }
}

struct Quiz: Equatable, Sendable {
    let generatedAt: Date?
    let questions: [QuizQuestion]
}

enum QuizError: Error, Equatable, Sendable {
    case notJSON
    case notAnObject
}

extension QuizError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notJSON: "El archivo del cuestionario no es un JSON válido."
        case .notAnObject: "El archivo del cuestionario no tiene el formato esperado."
        }
    }
}

/// Tolerant reader of `apuntes/cuestionario.json`. The type is taken from `type` or inferred from `options`; the
/// correct option may be given as its text, a letter ("B", "b) ..."), or a 1-based number. An unresolvable answer
/// degrades the question to self-evaluation instead of dropping it.
enum QuizParser {
    static func parse(_ data: Data) throws -> Quiz {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { throw QuizError.notJSON }
        let entries: [Any]
        var generatedAt: Date?
        if let root = object as? [String: Any] {
            entries = root["questions"] as? [Any] ?? []
            generatedAt = JSONText.string(root["generatedAt"]).flatMap(JSONText.date)
        } else if let array = object as? [Any] {
            entries = array
        } else {
            throw QuizError.notAnObject
        }

        var questions: [QuizQuestion] = []
        var seen: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            guard let dict = entry as? [String: Any], let prompt = JSONText.string(dict["question"]),
                  let answer = JSONText.identifier(dict["answer"]) else { continue }
            let options = JSONText.strings(dict["options"])
            let kind = kind(JSONText.string(dict["type"]), hasOptions: options.count >= 2)
            let correct = kind == .multipleChoice ? resolve(answer, in: options) : nil
            let base = JSONText.identifier(dict["id"]) ?? "q-\(index + 1)"
            let occurrence = (seen[base] ?? 0) + 1
            seen[base] = occurrence
            questions.append(QuizQuestion(
                id: occurrence == 1 ? base : "\(base)-\(occurrence)", kind: kind, prompt: prompt,
                options: kind == .multipleChoice ? options : [], correctIndex: correct,
                answer: correct.map { options[$0] } ?? answer,
                explanation: JSONText.string(dict["explanation"]), source: JSONText.string(dict["source"])))
        }
        return Quiz(generatedAt: generatedAt, questions: questions)
    }

    private static func kind(_ raw: String?, hasOptions: Bool) -> QuizQuestion.Kind {
        guard let raw = raw?.lowercased() else { return hasOptions ? .multipleChoice : .shortAnswer }
        if raw.contains("short") || raw.contains("corta") || raw.contains("abierta") || raw.contains("open") { return .shortAnswer }
        if raw.contains("multiple") || raw.contains("múltiple") || raw.contains("opcion") || raw.contains("opción") || raw == "mc" {
            return hasOptions ? .multipleChoice : .shortAnswer
        }
        return hasOptions ? .multipleChoice : .shortAnswer
    }

    private static func resolve(_ answer: String, in options: [String]) -> Int? {
        func norm(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let target = norm(answer)
        if let exact = options.firstIndex(where: { norm($0) == target }) { return exact }
        // "B", "b)", "B. texto"
        if let first = target.first, first.isLetter, let letter = first.asciiValue.map({ Int($0) - 97 }), (0..<options.count).contains(letter) {
            let rest = target.dropFirst()
            if rest.isEmpty || rest.hasPrefix(")") || rest.hasPrefix(".") || rest.hasPrefix(":") { return letter }
        }
        // 1-based number
        if let number = Int(target), (1...max(options.count, 1)).contains(number) { return number - 1 }
        return nil
    }
}

enum QuizLoadState: Equatable, Sendable {
    case missing
    case loaded(Quiz)
    case invalid(String)
}

enum QuizFile {
    static let relativePath = "apuntes/cuestionario.json"

    static func load(in courseFolder: URL) -> QuizLoadState {
        guard let data = try? Data(contentsOf: courseFolder.appendingPathComponent(relativePath)) else { return .missing }
        do { return .loaded(try QuizParser.parse(data)) } catch { return .invalid(error.localizedDescription) }
    }
}

struct QuizScore: Equatable, Sendable {
    let correct: Int
    let total: Int
    var percent: Double { total == 0 ? 0 : Double(correct) / Double(total) * 100 }
}

/// In-app practice: multiple choice is corrected immediately; short answers show the reference answer and the student
/// marks themselves correct or incorrect. Nothing is persisted.
struct QuizSession: Equatable, Sendable {
    let quiz: Quiz
    private(set) var position = 0
    private(set) var results: [String: Bool] = [:]
    private(set) var selectedChoice: Int?
    private(set) var isRevealed = false

    init(quiz: Quiz) { self.quiz = quiz }

    var current: QuizQuestion? { position < quiz.questions.count ? quiz.questions[position] : nil }
    var isFinished: Bool { current == nil }
    var isAnswered: Bool { current.flatMap { results[$0.id] } != nil }
    var score: QuizScore { QuizScore(correct: results.values.filter { $0 }.count, total: quiz.questions.count) }

    /// Answers the current multiple-choice question; nil when it is not auto-gradable or was already answered.
    @discardableResult
    mutating func submit(choice: Int) -> Bool? {
        guard let question = current, question.isAutoGradable, !isAnswered, (0..<question.options.count).contains(choice) else { return nil }
        let correct = choice == question.correctIndex
        selectedChoice = choice
        results[question.id] = correct
        isRevealed = true
        return correct
    }

    mutating func reveal() { if current != nil { isRevealed = true } }

    /// Self-evaluation of a question without an auto-gradable answer; requires the reference answer to be shown.
    mutating func selfEvaluate(correct: Bool) {
        guard let question = current, !question.isAutoGradable, isRevealed, !isAnswered else { return }
        results[question.id] = correct
    }

    mutating func advance() {
        guard isAnswered else { return }
        position += 1
        selectedChoice = nil
        isRevealed = false
    }
}
