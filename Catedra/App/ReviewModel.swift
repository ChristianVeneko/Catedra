import Foundation
import Observation

/// State of the "Repaso" destination: decks per course, the user's progress, and the active study or quiz session.
@Observable @MainActor
final class ReviewModel {
    enum Mode {
        case overview
        case studying(courseID: String)
        case quiz(courseID: String)
    }

    private(set) var progress = ReviewProgressFile()
    private(set) var deckStates: [String: FlashcardLoadState] = [:]
    var selectedCourseID: String?
    private(set) var mode: Mode = .overview
    private(set) var session: ReviewSession?
    private(set) var isAnswerRevealed = false
    private(set) var quizSession: QuizSession?
    private(set) var quizMessage: String?
    private(set) var saveError: String?
    private var rootURL: URL?
    private let store: ReviewProgressStoring

    init(store: ReviewProgressStoring = JSONReviewProgressStore()) {
        self.store = store
    }

    func load() { progress = store.load() }

    /// Re-reads every course's `tarjetas.json` and reconciles progress with it (never dropping any).
    func reload(courses: [Course], root: URL) {
        rootURL = root
        var states: [String: FlashcardLoadState] = [:]
        var next = progress
        for course in courses {
            let state = FlashcardFile.load(in: root.appendingPathComponent(course.folderName, isDirectory: true))
            states[course.folderName] = state
            if case .loaded(let deck) = state, let existing = next.courses[course.folderName] {
                let reconciled = ReviewPlanner.reconcile(cards: deck.cards, progress: existing)
                if reconciled != existing { next.courses[course.folderName] = reconciled }
            }
        }
        deckStates = states
        persistIfChanged(next)
    }

    // MARK: - Queries

    func cards(for courseID: String) -> [Flashcard] {
        if case .loaded(let deck)? = deckStates[courseID] { return deck.cards }
        return []
    }

    func state(for courseID: String) -> FlashcardLoadState { deckStates[courseID] ?? .missing }

    func counts(for courseID: String, today: ReviewDay) -> DeckCounts {
        ReviewPlanner.counts(cards: cards(for: courseID), progress: progress.courses[courseID] ?? [:], today: today,
                             newLimit: progress.settings.clampedNewCardsPerDay)
    }

    /// "Tarjetas para hoy" across all decks.
    func todayCount(today: ReviewDay) -> Int {
        deckStates.keys.reduce(0) { $0 + counts(for: $1, today: today).today }
    }

    var hasAnyCards: Bool { deckStates.values.contains { if case .loaded(let d) = $0 { !d.cards.isEmpty } else { false } } }

    var newCardsPerDay: Int { progress.settings.clampedNewCardsPerDay }

    // MARK: - Settings

    func setNewCardsPerDay(_ value: Int) {
        var next = progress
        next.settings.newCardsPerDay = min(max(value, 0), ReviewSettings.maxNewCardsPerDay)
        persistIfChanged(next)
    }

    // MARK: - Study session

    func startSession(courseID: String, now: Date = Date()) {
        let queue = ReviewPlanner.queue(cards: cards(for: courseID), progress: progress.courses[courseID] ?? [:],
                                        today: ReviewDay(date: now), newLimit: newCardsPerDay)
        guard !queue.isEmpty else { return }
        session = ReviewSession(cards: queue)
        isAnswerRevealed = false
        mode = .studying(courseID: courseID)
        selectedCourseID = courseID
    }

    func reveal() { if session?.current != nil { isAnswerRevealed = true } }

    /// Interval in days a grade would schedule for the current card (shown on the grade buttons).
    func previewInterval(for grade: ReviewGrade, courseID: String, now: Date = Date()) -> Int? {
        guard let card = session?.current else { return nil }
        let today = ReviewDay(date: now)
        return SM2Scheduler.review(progress.courses[courseID]?[card.id], grade: grade, today: today,
                                   fingerprint: card.fingerprint).interval
    }

    func grade(_ grade: ReviewGrade, courseID: String, now: Date = Date()) {
        guard isAnswerRevealed, var current = session, let outcome = current.grade(grade) else { return }
        session = current
        isAnswerRevealed = false
        guard outcome.recordsProgress else { return }
        var next = progress
        let today = ReviewDay(date: now)
        let previous = next.courses[courseID]?[outcome.card.id]
        next.courses[courseID, default: [:]][outcome.card.id] = SM2Scheduler.review(
            previous, grade: grade, today: today, fingerprint: outcome.card.fingerprint)
        persistIfChanged(next)
    }

    func endSession() {
        session = nil
        isAnswerRevealed = false
        mode = .overview
    }

    // MARK: - Quiz

    func startQuiz(courseID: String) {
        guard let root = rootURL else { return }
        quizMessage = nil
        switch QuizFile.load(in: root.appendingPathComponent(courseID, isDirectory: true)) {
        case .loaded(let quiz) where !quiz.questions.isEmpty:
            quizSession = QuizSession(quiz: quiz)
            mode = .quiz(courseID: courseID)
            selectedCourseID = courseID
        case .loaded:
            quizMessage = "El cuestionario no tiene preguntas. Vuelva a generarlo."
        case .invalid(let reason):
            quizMessage = "No se pudo leer el cuestionario. \(reason) Vuelva a generarlo."
        case .missing:
            quizMessage = "Aún no hay un cuestionario para esta materia."
        }
    }

    func updateQuiz(_ change: (inout QuizSession) -> Void) {
        guard var current = quizSession else { return }
        change(&current)
        quizSession = current
    }

    func endQuiz() {
        quizSession = nil
        mode = .overview
    }

    func hasQuiz(courseID: String) -> Bool {
        guard let root = rootURL else { return false }
        return FileManager.default.fileExists(
            atPath: root.appendingPathComponent(courseID, isDirectory: true).appendingPathComponent(QuizFile.relativePath).path)
    }

    // MARK: - Persistence

    private func persistIfChanged(_ next: ReviewProgressFile) {
        guard next != progress else { return }
        progress = next
        do {
            try store.save(next)
            saveError = nil
        } catch {
            saveError = "No se pudo guardar el progreso de repaso."
        }
    }
}
