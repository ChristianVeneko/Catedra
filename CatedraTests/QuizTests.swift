import Testing
import Foundation
@testable import Catedra

struct QuizParserTests {
    func parse(_ json: String) throws -> Quiz { try QuizParser.parse(Data(json.utf8)) }

    @Test func parsesMultipleChoiceAndShortAnswer() throws {
        let quiz = try parse("""
        {"generatedAt":"2026-10-05T14:30:00Z","questions":[
          {"id":"q1","type":"multiple-choice","question":"¿Unidad de la resistencia?","options":["Voltio","Ohmio","Amperio"],
           "answer":"Ohmio","explanation":"R se mide en ohmios.","source":"contenidos/U1/ohm.pdf"},
          {"id":"q2","type":"short-answer","question":"Enuncie la ley de Ohm.","answer":"V = I·R","explanation":"Relación lineal."}]}
        """)
        #expect(quiz.questions.count == 2)
        let mc = quiz.questions[0]
        #expect(mc.kind == .multipleChoice)
        #expect(mc.options == ["Voltio", "Ohmio", "Amperio"])
        #expect(mc.correctIndex == 1)
        #expect(mc.isAutoGradable)
        #expect(mc.explanation == "R se mide en ohmios.")
        #expect(mc.source == "contenidos/U1/ohm.pdf")
        let short = quiz.questions[1]
        #expect(short.kind == .shortAnswer)
        #expect(!short.isAutoGradable)
        #expect(short.answer == "V = I·R")
    }

    @Test func infersTypeFromOptions() throws {
        let quiz = try parse(#"{"questions":[{"question":"a","options":["x","y"],"answer":"y"},{"question":"b","answer":"z"}]}"#)
        #expect(quiz.questions.map(\.kind) == [.multipleChoice, .shortAnswer])
        #expect(quiz.questions.map(\.id) == ["q-1", "q-2"])
    }

    @Test func resolvesAnswerByLetterOrNumberOrFuzzyText() throws {
        let quiz = try parse("""
        {"questions":[
          {"question":"a","options":["x","y","z"],"answer":"C"},
          {"question":"b","options":["x","y","z"],"answer":"b) y"},
          {"question":"c","options":["x","y","z"],"answer":1},
          {"question":"d","options":["Uno","Dos"],"answer":"  dos "}]}
        """)
        #expect(quiz.questions.map(\.correctIndex) == [2, 1, 0, 1])
    }

    @Test func unresolvableAnswerDegradesToSelfEvaluation() throws {
        let quiz = try parse(#"{"questions":[{"question":"a","type":"multiple-choice","options":["x","y"],"answer":"nada que ver"}]}"#)
        #expect(quiz.questions[0].correctIndex == nil)
        #expect(!quiz.questions[0].isAutoGradable)
        #expect(quiz.questions[0].answer == "nada que ver")
    }

    @Test func skipsInvalidQuestions() throws {
        let quiz = try parse(#"{"questions":[{"answer":"x"},{"question":"sin respuesta"},{"question":"ok","answer":"x"},3]}"#)
        #expect(quiz.questions.map(\.prompt) == ["ok"])
    }

    @Test func acceptsTopLevelArrayAndDeduplicatesIds() throws {
        let quiz = try parse(#"[{"id":"a","question":"1","answer":"x"},{"id":"a","question":"2","answer":"y"}]"#)
        #expect(quiz.questions.map(\.id) == ["a", "a-2"])
    }

    @Test func rejectsGarbage() {
        #expect(throws: QuizError.notJSON) { try parse("x") }
        #expect(throws: QuizError.notAnObject) { try parse("1") }
    }

    @Test func loadStates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qz-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(QuizFile.load(in: dir) == .missing)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("apuntes"), withIntermediateDirectories: true)
        try Data(#"{"questions":[{"question":"q","answer":"a"}]}"#.utf8).write(to: dir.appendingPathComponent(QuizFile.relativePath))
        if case .loaded(let quiz) = QuizFile.load(in: dir) { #expect(quiz.questions.count == 1) } else { Issue.record("expected loaded") }
    }
}

struct QuizSessionTests {
    func quiz() throws -> Quiz {
        try QuizParser.parse(Data("""
        {"questions":[
          {"id":"m","options":["x","y"],"answer":"y","question":"mc"},
          {"id":"s","question":"short","answer":"ref"},
          {"id":"m2","options":["x","y"],"answer":"x","question":"mc2"}]}
        """.utf8))
    }

    @Test func multipleChoiceIsCorrectedImmediately() throws {
        var session = QuizSession(quiz: try quiz())
        #expect(session.submit(choice: 1) == true)
        #expect(session.isAnswered)
        #expect(session.selectedChoice == 1)
        #expect(session.submit(choice: 0) == nil) // locked after the first answer
        session.advance()
        #expect(session.current?.id == "s")
        #expect(!session.isAnswered)
    }

    @Test func shortAnswerIsSelfEvaluated() throws {
        var session = QuizSession(quiz: try quiz())
        _ = session.submit(choice: 0)
        session.advance()
        #expect(session.submit(choice: 0) == nil) // not a multiple-choice question
        session.reveal()
        #expect(session.isRevealed)
        session.selfEvaluate(correct: true)
        #expect(session.isAnswered)
        session.advance()
        #expect(session.current?.id == "m2")
    }

    @Test func finalScoreCountsCorrectAnswers() throws {
        var session = QuizSession(quiz: try quiz())
        _ = session.submit(choice: 1); session.advance()       // correct
        session.reveal(); session.selfEvaluate(correct: false); session.advance()
        _ = session.submit(choice: 1); session.advance()       // wrong (answer is index 0)
        #expect(session.isFinished)
        #expect(session.score == QuizScore(correct: 1, total: 3))
        #expect(abs(session.score.percent - 100.0 / 3.0) < 1e-9)
    }

    @Test func selfEvaluationRequiresRevealAndOnlyOnce() throws {
        var session = QuizSession(quiz: try quiz())
        _ = session.submit(choice: 1); session.advance()
        session.selfEvaluate(correct: true)
        #expect(!session.isAnswered) // not revealed yet
        session.reveal()
        session.selfEvaluate(correct: true)
        session.selfEvaluate(correct: false)
        #expect(session.results["s"] == true)
    }

    @Test func advanceRequiresAnAnswer() throws {
        var session = QuizSession(quiz: try quiz())
        session.advance()
        #expect(session.current?.id == "m")
    }

    @Test func emptyQuizIsFinishedWithZeroScore() {
        let session = QuizSession(quiz: Quiz(generatedAt: nil, questions: []))
        #expect(session.isFinished)
        #expect(session.score == QuizScore(correct: 0, total: 0))
        #expect(session.score.percent == 0)
    }
}
