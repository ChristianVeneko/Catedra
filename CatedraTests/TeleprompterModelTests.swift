import Testing
import Foundation
@testable import Catedra

@MainActor
private final class FakeTranscriber: SpeechTranscribing {
    var authorization: SpeechAuthorization = .authorized
    var startError: Error?
    private(set) var startedLanguages: [String] = []
    private(set) var stops = 0
    private var continuation: AsyncStream<String>.Continuation?

    func requestAuthorization() async -> SpeechAuthorization { authorization }

    func start(language: String) throws -> AsyncStream<String> {
        if let startError { throw startError }
        startedLanguages.append(language)
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() {
        stops += 1
        continuation?.finish()
        continuation = nil
    }

    func say(_ text: String) { continuation?.yield(text) }
    /// The recognizer giving up on its own (not through `stop()`).
    func giveUp() { continuation?.finish(); continuation = nil }
}

@MainActor
private final class FakePresenter: TeleprompterPresenting {
    private(set) var visible = false
    func show() { visible = true }
    func hide() { visible = false }
}

@MainActor
struct TeleprompterModelTests {
    private let source = """
    ---
    idioma: es-MX
    ---
    ## Intro
    Buenos días profesor. Hoy presento el avance.

    ## Demo
    Abro la aplicación. Muestro el calendario.
    """

    private func makeModel(_ transcriber: FakeTranscriber = FakeTranscriber(), mode: TeleprompterModel.Mode = .voice)
        -> (TeleprompterModel, FakeTranscriber, FakePresenter) {
        let defaults = UserDefaults(suiteName: "TeleprompterModelTests-\(UUID().uuidString)")!
        let presenter = FakePresenter()
        let model = TeleprompterModel(transcriber: transcriber, presenter: presenter, defaults: defaults)
        model.preferredMode = mode
        return (model, transcriber, presenter)
    }

    @Test func startingShowsTheIslandAndListensInTheScriptLanguage() async {
        let (model, transcriber, presenter) = makeModel()
        await model.start(ScriptParser.parse(source))
        #expect(presenter.visible)
        #expect(model.state == .running)
        #expect(model.activeMode == .voice)
        #expect(transcriber.startedLanguages == ["es-MX"])
    }

    @Test func voiceTranscriptsMoveThePosition() async {
        let (model, transcriber, _) = makeModel()
        await model.start(ScriptParser.parse(source))
        transcriber.say("buenos días")
        transcriber.say("buenos días profesor")
        for _ in 0..<50 where model.position < 3 { await Task.yield() }
        #expect(model.position == 3)
        #expect(model.currentSentence == 1)
    }

    @Test func deniedPermissionFallsBackToFixedPaceWithANotice() async {
        let transcriber = FakeTranscriber()
        transcriber.authorization = .denied
        let (model, _, _) = makeModel(transcriber)
        await model.start(ScriptParser.parse(source))
        #expect(model.activeMode == .pace)
        #expect(model.notice?.contains("ritmo fijo") == true)
        #expect(transcriber.startedLanguages.isEmpty)
    }

    @Test func paceModeAdvancesOneWordPerTickAndFinishes() async {
        let (model, transcriber, _) = makeModel(mode: .pace)
        await model.start(ScriptParser.parse("Uno dos tres."))
        #expect(transcriber.startedLanguages.isEmpty)
        model.tick(); model.tick()
        #expect(model.position == 2)
        model.tick()
        #expect(model.state == .finished)
        model.tick()
        #expect(model.position == 3)
    }

    @Test func sentenceAndSectionMovesReanchorTheVoice() async {
        let (model, _, _) = makeModel()
        await model.start(ScriptParser.parse(source))
        model.nextSentence()
        #expect(model.position == 3)
        model.nextSection()
        #expect(model.position == 7)
        #expect(model.currentSection == 1)
        model.receive(transcript: "abro la aplicación")
        #expect(model.position == 10)
        model.previousSentence()
        #expect(model.position == 7)
        model.previousSection()
        #expect(model.position == 0)
    }

    @Test func pauseStopsListeningAndResumeStartsAgain() async {
        let (model, transcriber, _) = makeModel()
        await model.start(ScriptParser.parse(source))
        model.togglePause()
        #expect(model.state == .paused)
        #expect(transcriber.stops == 1)
        model.receive(transcript: "buenos días profesor")
        #expect(model.position == 0)
        model.togglePause()
        #expect(model.state == .running)
        #expect(transcriber.startedLanguages.count == 2)
    }

    @Test func recognizerGivingUpFallsBackToFixedPace() async {
        let (model, transcriber, _) = makeModel()
        await model.start(ScriptParser.parse(source))
        transcriber.giveUp()
        for _ in 0..<50 where model.activeMode == .voice { await Task.yield() }
        #expect(model.activeMode == .pace)
        #expect(model.state == .running)
        #expect(model.notice?.contains("ritmo fijo") == true)
    }

    @Test func resumingAtTheEndFinishes() async {
        let (model, transcriber, _) = makeModel()
        await model.start(ScriptParser.parse(source))
        model.togglePause()
        model.nextSection(); model.nextSentence(); model.nextSentence()
        #expect(model.state == .paused)
        model.togglePause()
        #expect(model.state == .finished)
        #expect(transcriber.startedLanguages.count == 1)
    }

    @Test func closeHidesAndStops() async {
        let (model, transcriber, presenter) = makeModel()
        await model.start(ScriptParser.parse(source))
        model.close()
        #expect(!presenter.visible)
        #expect(model.state == .idle)
        #expect(model.script == nil)
        #expect(transcriber.stops == 1)
    }

    @Test func openingAMissingFileShowsANotice() async {
        let (model, _, presenter) = makeModel()
        await model.open(url: URL(fileURLWithPath: "/nonexistent/guion.md"))
        #expect(model.notice?.hasPrefix("No se pudo abrir el guion") == true)
        #expect(!presenter.visible)
    }

    @Test func preferencesPersist() {
        let defaults = UserDefaults(suiteName: "TeleprompterModelTests-prefs-\(UUID().uuidString)")!
        let first = TeleprompterModel(transcriber: FakeTranscriber(), presenter: nil, defaults: defaults)
        first.preferredMode = .pace
        first.wordsPerMinute = 160
        first.fontSize = 26
        #expect(first.hiddenFromCapture)
        first.hiddenFromCapture = false
        let second = TeleprompterModel(transcriber: FakeTranscriber(), presenter: nil, defaults: defaults)
        #expect(second.preferredMode == .pace)
        #expect(second.wordsPerMinute == 160)
        #expect(second.fontSize == 26)
        #expect(!second.hiddenFromCapture)
    }
}
