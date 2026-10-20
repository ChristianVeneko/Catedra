import AVFoundation
import Foundation
import Speech
import os

/// Microphone + `SFSpeechRecognizer`, on device when the language supports it.
/// Recognition requests are short-lived, so each final result or error starts a new request on the same audio tap;
/// the stream keeps going until `stop()` (or several errors in a row).
@MainActor
final class AppleSpeechTranscriber: SpeechTranscribing {
    enum TranscriberError: LocalizedError {
        case unavailable(String)
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .unavailable(let language): "no hay reconocimiento de voz para «\(language)» en este Mac"
            case .noMicrophone: "no hay ningún micrófono conectado"
            }
        }
    }

    static let maxConsecutiveFailures = 3
    /// An error this soon after a request started means recognition cannot run (a restart loop), not a silence timeout.
    static let quickFailure: TimeInterval = 1.5
    private static let log = Logger(subsystem: "com.cmendoza.catedra", category: "speech")

    private lazy var engine = AVAudioEngine()
    private let box = RequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<String>.Continuation?
    private var failures = 0
    private var running = false
    /// Bumped for every request and on stop, so callbacks of an older request are ignored.
    private var generation = 0
    private var requestStarted = Date()
    /// Cleared after repeated quick failures on device, to retry with Apple's server recognition.
    private var preferOnDevice = true

    func requestAuthorization() async -> SpeechAuthorization {
        guard SFSpeechRecognizer() != nil else { return .unavailable }
        let speech = await Self.speechAuthorization()
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
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TranscriberError.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(for: box))
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
        preferOnDevice = true
        beginRequest()
        return stream
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
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
        if preferOnDevice, recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        requestStarted = Date()
        generation += 1
        task?.cancel()
        box.replace(with: request)?.endAudio()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self, generation: generation))
    }

    fileprivate func handle(text: String?, isFinal: Bool, error: String?, generation: Int) {
        guard running, generation == self.generation else { return }
        if let text, !text.isEmpty {
            failures = 0
            continuation?.yield(text)
        }
        guard isFinal || error != nil else { return }
        if let error, text == nil {
            let elapsed = Date().timeIntervalSince(requestStarted)
            Self.log.notice("recognition ended after \(elapsed, format: .fixed(precision: 1))s: \(error, privacy: .public)")
            // Silence timeouts ("no speech detected") arrive after a while: just start the next request.
            failures = elapsed < Self.quickFailure ? failures + 1 : 0
            if failures >= Self.maxConsecutiveFailures {
                guard preferOnDevice, recognizer?.supportsOnDeviceRecognition == true else { stop(); return }
                Self.log.notice("on-device recognition keeps failing; retrying with server recognition")
                preferOnDevice = false
                failures = 0
            }
        }
        beginRequest()
    }

    // MARK: - Callbacks
    // Built in nonisolated functions on purpose: closures written inside this @MainActor class would inherit main-actor
    // isolation, and Swift 6 traps when AVFAudio / Speech call them from their own threads.

    nonisolated static func tapBlock(for box: RequestBox) -> AVAudioNodeTapBlock {
        { buffer, _ in box.append(buffer) }
    }

    nonisolated static func resultHandler(for owner: AppleSpeechTranscriber, generation: Int)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map { "\(($0 as NSError).domain) \(($0 as NSError).code): \($0.localizedDescription)" }
            Task { @MainActor in owner.handle(text: text, isFinal: isFinal, error: failure, generation: generation) }
        }
    }

    nonisolated private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
    }
}

/// The audio tap runs on a real-time thread; it reaches the current request only through this lock.
final class RequestBox: @unchecked Sendable {
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
