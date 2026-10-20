import Foundation
import Observation

/// Runs a script on the notch island: follows the speaker's voice (or a fixed reading pace) and exposes the
/// position for the view. Manual moves (sentence / section) re-anchor the voice aligner.
@Observable @MainActor
final class TeleprompterModel {
    enum Mode: String, CaseIterable, Sendable {
        case voice
        case pace
    }

    enum State: Equatable, Sendable {
        case idle
        case running
        case paused
        case finished
    }

    static let defaultLanguage = "es-VE"

    private(set) var script: Script?
    private(set) var fileURL: URL?
    private(set) var state: State = .idle
    /// Script words already spoken; the next expected word is `script.words[position]`.
    private(set) var position = 0
    /// Mode actually in use; voice falls back to pace when recognition is unavailable.
    private(set) var activeMode: Mode = .voice
    private(set) var notice: String?

    var preferredMode: Mode {
        didSet { defaults.set(preferredMode.rawValue, forKey: Keys.mode) }
    }
    var wordsPerMinute: Double {
        didSet { defaults.set(wordsPerMinute, forKey: Keys.pace) }
    }
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }
    /// Keep the island out of screenshots and screen recordings that honor `NSWindow.sharingType`.
    var hiddenFromCapture: Bool {
        didSet { defaults.set(hiddenFromCapture, forKey: Keys.hiddenFromCapture) }
    }

    private let transcriber: SpeechTranscribing
    private weak var presenter: TeleprompterPresenting?
    private let defaults: UserDefaults
    private var aligner: ScriptAligner?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var isListening = false
    @ObservationIgnored private var ticker: Task<Void, Never>?

    private enum Keys {
        static let mode = "teleprompter.mode"
        static let pace = "teleprompter.wordsPerMinute"
        static let fontSize = "teleprompter.fontSize"
        static let hiddenFromCapture = "teleprompter.hiddenFromCapture"
    }

    init(transcriber: SpeechTranscribing, presenter: TeleprompterPresenting?, defaults: UserDefaults = .standard) {
        self.transcriber = transcriber
        self.presenter = presenter
        self.defaults = defaults
        preferredMode = defaults.string(forKey: Keys.mode).flatMap(Mode.init(rawValue:)) ?? .voice
        let pace = defaults.double(forKey: Keys.pace)
        wordsPerMinute = pace > 0 ? pace : 140
        let size = defaults.double(forKey: Keys.fontSize)
        fontSize = size > 0 ? size : 20
        hiddenFromCapture = defaults.object(forKey: Keys.hiddenFromCapture) as? Bool ?? true
    }

    func attach(presenter: TeleprompterPresenting) { self.presenter = presenter }

    var isActive: Bool { state != .idle }
    var currentSentence: Int { script?.sentenceIndex(forWord: position) ?? 0 }
    var currentSection: Int { script.map { $0.sentences.isEmpty ? 0 : $0.sentences[currentSentence].section } ?? 0 }
    var progress: Double {
        guard let script, !script.words.isEmpty else { return 0 }
        return Double(position) / Double(script.words.count)
    }

    // MARK: - Opening

    /// Reads a script file and starts it. Errors are shown as a notice and leave the island closed.
    func open(url: URL) async {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let script = ScriptParser.parse(source, fallbackTitle: url.deletingPathExtension().lastPathComponent)
            guard !script.isEmpty else { notice = "El guion «\(script.title)» no tiene texto para leer."; return }
            await start(script, url: url)
        } catch {
            notice = "No se pudo abrir el guion: \(error.localizedDescription)"
        }
    }

    func start(_ script: Script, url: URL? = nil) async {
        stopTracking()
        self.script = script
        fileURL = url
        aligner = ScriptAligner(script: script)
        position = 0
        notice = nil
        state = .running
        presenter?.show()
        activeMode = await resolvedMode()
        resumeTracking()
    }

    // MARK: - Controls

    func togglePause() {
        switch state {
        case .running:
            stopTracking()
            state = .paused
        case .paused:
            state = .running
            resumeTracking()
        case .finished:
            restartFromSentence(0)
        case .idle:
            break
        }
    }

    func nextSentence() { moveSentence(by: 1) }
    func previousSentence() { moveSentence(by: -1) }

    func nextSection() { moveSection(by: 1) }
    func previousSection() { moveSection(by: -1) }

    func close() {
        stopTracking()
        state = .idle
        script = nil
        fileURL = nil
        aligner = nil
        position = 0
        presenter?.hide()
    }

    func dismissNotice() { notice = nil }

    /// A problem outside a running script (bad link, missing file): shown in the island only if it is open.
    func report(_ message: String) { notice = message }

    // MARK: - Tracking (exposed for tests)

    /// Applies one recognizer transcript.
    func receive(transcript: String) {
        guard state == .running, var aligner else { return }
        aligner.update(transcript: transcript)
        self.aligner = aligner
        setPosition(aligner.position)
    }

    /// One fixed-pace step: the next word.
    func tick() {
        guard state == .running else { return }
        moveTo(word: position + 1)
    }

    // MARK: - Internals

    private func resolvedMode() async -> Mode {
        guard preferredMode == .voice else { return .pace }
        switch await transcriber.requestAuthorization() {
        case .authorized:
            return .voice
        case .denied:
            notice = "Sin permiso de micrófono o reconocimiento de voz: el guion avanza a ritmo fijo. Actívalo en Ajustes del Sistema > Privacidad."
        case .unavailable:
            notice = "El reconocimiento de voz no está disponible para este idioma: el guion avanza a ritmo fijo."
        }
        return .pace
    }

    private func resumeTracking() {
        guard state == .running else { return }
        switch activeMode {
        case .voice: startListening()
        case .pace: startTicker()
        }
    }

    private func startListening() {
        let stream: AsyncStream<String>
        do {
            stream = try transcriber.start(language: script?.language ?? Self.defaultLanguage)
        } catch {
            notice = "No se pudo iniciar el micrófono: \(error.localizedDescription). El guion avanza a ritmo fijo."
            activeMode = .pace
            startTicker()
            return
        }
        isListening = true
        listener = Task { [weak self] in
            for await transcript in stream {
                guard let self, !Task.isCancelled else { return }
                self.receive(transcript: transcript)
            }
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                let pace = max(self?.wordsPerMinute ?? 140, 40)
                try? await Task.sleep(for: .seconds(60 / pace))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func stopTracking() {
        listener?.cancel()
        listener = nil
        ticker?.cancel()
        ticker = nil
        if isListening {
            transcriber.stop()
            isListening = false
        }
    }

    private func moveSentence(by delta: Int) {
        guard let script, !script.sentences.isEmpty else { return }
        // Going back from the middle of a sentence first returns to its start.
        let current = currentSentence
        let start = script.firstWord(ofSentence: current) ?? 0
        let target = delta < 0 && position > start ? current : current + delta
        restartFromSentence(min(max(target, 0), script.sentences.count))
    }

    private func moveSection(by delta: Int) {
        guard let script, !script.sections.isEmpty else { return }
        let target = min(max(currentSection + delta, 0), script.sections.count - 1)
        restartFromSentence(script.sections[target].sentences.lowerBound)
    }

    private func restartFromSentence(_ sentence: Int) {
        guard let script else { return }
        let word = sentence >= script.sentences.count ? script.words.count : (script.firstWord(ofSentence: sentence) ?? script.words.count)
        let wasFinished = state == .finished
        moveTo(word: word)
        if wasFinished, state != .finished {
            state = .running
            resumeTracking()
        }
    }

    private func moveTo(word: Int) {
        aligner?.jump(to: word)
        setPosition(aligner?.position ?? 0)
    }

    private func setPosition(_ value: Int) {
        position = value
        guard let script else { return }
        if position >= script.words.count, state == .running {
            stopTracking()
            state = .finished
        } else if position < script.words.count, state == .finished {
            state = .paused
        }
    }
}
