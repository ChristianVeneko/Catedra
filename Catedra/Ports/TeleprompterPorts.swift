import Foundation

enum SpeechAuthorization: Equatable, Sendable {
    case authorized
    /// Microphone or speech recognition denied in System Settings.
    case denied
    /// No recognizer for the language on this Mac.
    case unavailable
}

/// Live speech-to-text from the microphone, on device.
@MainActor
protocol SpeechTranscribing: AnyObject {
    func requestAuthorization() async -> SpeechAuthorization
    /// Partial transcripts of the current utterance; a new utterance may restart from empty text.
    /// The stream finishes when `stop()` is called or recognition fails.
    func start(language: String) throws -> AsyncStream<String>
    func stop()
}

/// The floating island that shows the script (the notch panel in the app).
@MainActor
protocol TeleprompterPresenting: AnyObject {
    func show()
    func hide()
}
