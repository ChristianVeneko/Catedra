import Testing
import Foundation
@testable import Catedra

struct ScriptAlignerTests {
    private let text = "Buenos días profesor. Hoy les presento el avance de la fase dos del proyecto. "
        + "Primero veremos la arquitectura de la aplicación. Después haremos una demostración en vivo con datos reales."

    private func aligner() -> ScriptAligner { ScriptAligner(script: ScriptParser.parse(text)) }

    /// Feeds a growing transcript the way the recognizer reports partial results.
    private func speak(_ aligner: inout ScriptAligner, _ phrase: String) {
        var heard: [String] = []
        for word in phrase.split(separator: " ") {
            heard.append(String(word))
            aligner.update(transcript: heard.joined(separator: " "))
        }
    }

    @Test func followsTheSpeakerWordByWord() {
        var a = aligner()
        #expect(a.position == 0)
        speak(&a, "Buenos días profesor")
        #expect(a.position == 3)
        speak(&a, "hoy les presento")
        #expect(a.position == 6)
    }

    @Test func toleratesMisrecognizedWordsAndAccents() {
        var a = aligner()
        speak(&a, "buenos dias profesora hoy les presente el abance")
        #expect(a.position == 8)
    }

    @Test func repeatingEarlierWordsNeverGoesBack() {
        var a = aligner()
        speak(&a, "Buenos días profesor hoy les presento el avance")
        let before = a.position
        a.update(transcript: "buenos días profesor")
        #expect(a.position == before)
    }

    @Test func improvisingHoldsThePosition() {
        var a = aligner()
        speak(&a, "Buenos días profesor")
        speak(&a, "perdón se me cayó el micrófono un momento")
        #expect(a.position == 3)
    }

    @Test func aLoneCommonWordDoesNotJumpAhead() {
        var a = aligner()
        speak(&a, "Buenos días profesor")
        a.update(transcript: "de")
        #expect(a.position == 3)
    }

    @Test func skippingASentenceAdvancesToWhatIsSaid() {
        var a = aligner()
        speak(&a, "Buenos días profesor")
        speak(&a, "primero veremos la arquitectura")
        #expect(a.position == 18)
    }

    @Test func farJumpsNeedAStrongMatch() {
        var a = aligner()
        speak(&a, "Buenos días profesor")
        speak(&a, "una demostración en vivo")
        #expect(a.position == 27)
    }

    @Test func restartedTranscriptKeepsFollowing() {
        var a = aligner()
        speak(&a, "Buenos días profesor hoy les")
        speak(&a, "presento el avance")
        #expect(a.position == 8)
    }

    @Test func manualMovesClampToTheScript() {
        var a = aligner()
        a.jump(to: 1000)
        #expect(a.position == a.wordCount)
        #expect(a.isFinished)
        a.jump(to: -4)
        #expect(a.position == 0)
    }
}
