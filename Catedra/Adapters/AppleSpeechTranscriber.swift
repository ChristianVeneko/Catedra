import AVFoundation
import Foundation
import Speech

/// Microphone + `SFSpeechRecognizer`, on device when the language supports it.
/// Recognition requests are short-lived, so each final result or error starts a new request on the same audio tap;
/// the stream keeps going until `stop()` (or several errors in a row).
@MainActor
final class AppleSpeechTranscriber: SpeechTranscribing {
    enum TranscriberError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let language): "no hay reconocimiento de voz para «\(language)» en este Mac"
            }
        }
    }

    static let maxConsecutiveFailures = 3

    private lazy var engine = AVAudioEngine()
    private let box = RequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<String>.Continuation?
    private var failures = 0
    private var running = false

    func requestAuthorization() async -> SpeechAuthorization {
        guard SFSpeechRecognizer() != nil else { return .unavailable }
        let speech = await withCheckedContinuation { (done: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        guard speech == .authorized else { return .denied }
        return await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
    }

    func start(language: String) throws -> AsyncStream<String> {
        stop()
        let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
        guard let identifier = Self.bestLocale(for: language, supported: supported),
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)), recognizer.isAvailable else {
            throw TranscriberError.unavailable(language)
        }
        recognizer.defaultTaskHint = .dictation
        self.recognizer = recognizer

        let input = engine.inputNode
        let box = box
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            box.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.continuation = continuation
        running = true
        failures = 0
        beginRequest()
        return stream
    }

    func stop() {
        guard running else { return }
        running = false
        task?.cancel()
        task = nil
        box.replace(with: nil)?.endAudio()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
    }

    /// Exact identifier (`es-VE` / `es_VE`), else the same language preferring `es-US`, `es-MX`, `es-ES`, else any variant.
    nonisolated static func bestLocale(for language: String, supported: Set<String>) -> String? {
        let wanted = language.replacingOccurrences(of: "_", with: "-")
        let byDash = Dictionary(supported.map { ($0.replacingOccurrences(of: "_", with: "-"), $0) }, uniquingKeysWith: { a, _ in a })
        if let exact = byDash[wanted] { return exact }
        let base = String(wanted.prefix { $0 != "-" }).lowercased()
        for preferred in ["\(base)-US", "\(base)-MX", "\(base)-ES"] {
            if let match = byDash[preferred] { return match }
        }
        return byDash.keys.sorted().first { $0.lowercased().hasPrefix(base + "-") || $0.lowercased() == base }.flatMap { byDash[$0] }
    }

    // MARK: - Requests

    private func beginRequest() {
        guard running, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        box.replace(with: request)?.endAudio()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard running else { return }
        if let text, !text.isEmpty {
            failures = 0
            continuation?.yield(text)
        }
        guard isFinal || failed else { return }
        if failed, text == nil {
            failures += 1
            if failures >= Self.maxConsecutiveFailures { stop(); return }
        }
        beginRequest()
    }
}

/// The audio tap runs on a real-time thread; it reaches the current request only through this lock.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }

    /// Swaps the current request, returning the previous one so the caller can end it.
    @discardableResult
    func replace(with new: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = request
        request = new
        return old
    }
}
