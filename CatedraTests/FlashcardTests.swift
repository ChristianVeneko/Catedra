import Testing
import Foundation
@testable import Catedra

struct FlashcardParserTests {
    func parse(_ json: String) throws -> FlashcardDeck { try FlashcardParser.parse(Data(json.utf8)) }

    @Test func parsesFullDocument() throws {
        let deck = try parse("""
        {"generatedAt":"2026-10-05T14:30:00Z","cards":[
          {"id":"u1-ohm","question":"¿Qué dice la ley de Ohm?","answer":"V = I·R","source":"contenidos/U1/ohm.pdf","tags":["u1","ohm"]},
          {"id":"u1-kirchhoff","question":"¿Qué es un nodo?","answer":"Punto de unión"}]}
        """)
        #expect(deck.generatedAt == ISO8601DateFormatter().date(from: "2026-10-05T14:30:00Z"))
        #expect(deck.cards.map(\.id) == ["u1-ohm", "u1-kirchhoff"])
        #expect(deck.cards[0].source == "contenidos/U1/ohm.pdf")
        #expect(deck.cards[0].tags == ["u1", "ohm"])
        #expect(deck.cards[1].source == nil)
        #expect(deck.cards[1].tags == [])
    }

    @Test func acceptsTopLevelArray() throws {
        let deck = try parse(#"[{"id":"a","question":"q","answer":"r"}]"#)
        #expect(deck.cards.count == 1)
        #expect(deck.generatedAt == nil)
    }

    @Test func skipsCardsWithoutQuestionOrAnswer() throws {
        let deck = try parse(#"{"cards":[{"id":"a","question":"q"},{"id":"b","answer":"r"},{"id":"c","question":" ","answer":"r"},{"id":"d","question":"q","answer":"r"},"junk",7]}"#)
        #expect(deck.cards.map(\.id) == ["d"])
    }

    @Test func missingIdGetsStableFingerprintId() throws {
        let one = try parse(#"{"cards":[{"question":"¿Qué es un nodo?","answer":"x"}]}"#)
        let two = try parse(#"{"cards":[{"question":"  ¿QUE es   un nodo? ","answer":"y"}]}"#)
        #expect(one.cards[0].id.hasPrefix("card-"))
        #expect(one.cards[0].id == two.cards[0].id)
    }

    @Test func duplicateIdsAreDisambiguatedInOrder() throws {
        let deck = try parse(#"{"cards":[{"id":"a","question":"q1","answer":"r"},{"id":"a","question":"q2","answer":"r"},{"id":"a","question":"q3","answer":"r"}]}"#)
        #expect(deck.cards.map(\.id) == ["a", "a-2", "a-3"])
    }

    @Test func tagsAcceptASingleString() throws {
        let deck = try parse(#"{"cards":[{"id":"a","question":"q","answer":"r","tags":"u1"}]}"#)
        #expect(deck.cards[0].tags == ["u1"])
    }

    @Test func numericIdsAreAccepted() throws {
        let deck = try parse(#"{"cards":[{"id":12,"question":"q","answer":"r"}]}"#)
        #expect(deck.cards[0].id == "12")
    }

    @Test func rejectsNonJSONAndNonContainers() {
        #expect(throws: FlashcardError.notJSON) { try parse("hola") }
        #expect(throws: FlashcardError.notAnObject) { try parse("42") }
    }

    @Test func fingerprintIgnoresCaseAccentsAndSpacing() {
        #expect(Flashcard.fingerprint(of: "¿Qué  es?") == Flashcard.fingerprint(of: "¿que es?"))
        #expect(Flashcard.fingerprint(of: "a") != Flashcard.fingerprint(of: "b"))
    }

    @Test func loadStates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FlashcardFile.load(in: dir) == .missing)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("apuntes"), withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(FlashcardFile.relativePath)
        try Data("garbage".utf8).write(to: url)
        if case .invalid = FlashcardFile.load(in: dir) {} else { Issue.record("expected invalid") }
        try Data(#"{"cards":[{"id":"a","question":"q","answer":"r"}]}"#.utf8).write(to: url)
        if case .loaded(let deck) = FlashcardFile.load(in: dir) { #expect(deck.cards.count == 1) } else { Issue.record("expected loaded") }
    }
}
