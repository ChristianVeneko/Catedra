import Testing
import Foundation
@testable import Catedra

struct ScriptParserTests {
    @Test func readsFrontmatter() {
        let script = ScriptParser.parse("""
        ---
        titulo: Presentación de la fase 2
        duracion: 2m30s
        idioma: es-VE
        ---
        Hola.
        """)
        #expect(script.title == "Presentación de la fase 2")
        #expect(script.targetDuration == 150)
        #expect(script.language == "es-VE")
    }

    @Test func titleFallsBackToFirstH1ThenFileName() {
        #expect(ScriptParser.parse("# Mi guion\n\nHola.").title == "Mi guion")
        #expect(ScriptParser.parse("Hola.", fallbackTitle: "demo").title == "demo")
    }

    @Test func splitsSectionsAndSentences() {
        let script = ScriptParser.parse("""
        Intro breve.

        ## Diapositiva 1
        Buenos días, profesor. ¿Cómo están? Hoy presento
        el avance.

        ## Demo
        - Abro la app
        """)
        #expect(script.sections.map(\.title) == ["", "Diapositiva 1", "Demo"])
        #expect(script.sentences.map(\.text) == [
            "Intro breve.", "Buenos días, profesor.", "¿Cómo están?", "Hoy presento el avance.", "Abro la app",
        ])
        #expect(script.sentences.map(\.section) == [0, 1, 1, 1, 2])
        #expect(script.sections[1].sentences == 1..<4)
    }

    @Test func cuesAreShownButNotSpoken() {
        let script = ScriptParser.parse("Hoy les presento [pausa] el avance. [clic]")
        #expect(script.words.map(\.text) == ["Hoy", "les", "presento", "el", "avance."])
        #expect(script.sentences[0].tokens == [
            .word(0), .word(1), .word(2), .cue("pausa"), .word(3), .word(4), .cue("clic"),
        ])
    }

    @Test func wordsAreNormalizedForMatching() {
        let script = ScriptParser.parse("¡Educación **física**, señor!")
        #expect(script.words.map(\.normalized) == ["educacion", "fisica", "senor"])
        #expect(script.words.map(\.text) == ["¡Educación", "física,", "señor!"])
    }

    @Test func parsesDurationFormats() {
        #expect(ScriptParser.duration("3m") == 180)
        #expect(ScriptParser.duration("3 min") == 180)
        #expect(ScriptParser.duration("90s") == 90)
        #expect(ScriptParser.duration("1:30") == 90)
        #expect(ScriptParser.duration("rápido") == nil)
    }

    @Test func estimatesReadingTime() {
        let script = ScriptParser.parse(Array(repeating: "palabra", count: 140).joined(separator: " "))
        #expect(script.estimatedDuration(wordsPerMinute: 140) == 60)
    }
}
