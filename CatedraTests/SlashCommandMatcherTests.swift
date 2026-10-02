import Testing
import Foundation
@testable import Catedra

struct SlashCommandMatcherTests {
    private func cmd(_ name: String, _ description: String = "", aliases: [String] = [], kind: SlashCommand.Kind = .skill) -> SlashCommand {
        SlashCommand(name: name, description: description, argumentHint: nil, aliases: aliases, kind: kind)
    }

    private let catalog: [SlashCommand] = [
        SlashCommand(name: "compact", description: "Resume la conversación", argumentHint: nil, aliases: [], kind: .builtin),
        SlashCommand(name: "clear", description: "Limpia", argumentHint: nil, aliases: ["reset", "new"], kind: .builtin),
        SlashCommand(name: "anthropic-skills:docx", description: "Crea documentos Word", argumentHint: nil, aliases: [], kind: .skill),
        SlashCommand(name: "normas-uft", description: "Formato académico", argumentHint: "[name]", aliases: [], kind: .skill),
        SlashCommand(name: "docs", description: "Busca en la documentación", argumentHint: nil, aliases: [], kind: .skill),
        SlashCommand(name: "review", description: "Revisa un compactado", argumentHint: nil, aliases: [], kind: .builtin),
    ]

    private func names(_ query: String, limit: Int = 20) -> [String] {
        SlashCommandMatcher.match(query: query, in: catalog, limit: limit).map(\.command.name)
    }

    @Test func emptyQueryReturnsEverythingLimited() {
        #expect(names("").count == catalog.count)
        #expect(names("", limit: 2).count == 2)
    }

    @Test func namePrefixBeatsEverythingElse() {
        let result = names("co")
        #expect(result.first == "compact")
        #expect(result.contains("review")) // description contains "compactado"
    }

    @Test func exactMatchRanksFirst() {
        #expect(names("docs").first == "docs")
        #expect(names("doc").first == "docs") // shorter prefix match first
    }

    @Test func aliasPrefixRanksAboveSubstring() {
        let result = names("res")
        #expect(result.first == "clear") // alias "reset"
    }

    @Test func wordBoundaryAndSubstringOnName() {
        #expect(names("docx").first == "anthropic-skills:docx")
        #expect(names("uft") == ["normas-uft"])
    }

    @Test func descriptionIsLastResort() {
        #expect(names("word") == ["anthropic-skills:docx"])
    }

    @Test func isCaseAndDiacriticInsensitive() {
        #expect(names("ACADEMICO") == ["normas-uft"])
        #expect(names("DOCUMENTACION").contains("docs"))
        #expect(names("Compact").first == "compact")
    }

    @Test func subsequenceFuzzyMatchesLast() {
        #expect(names("dcx").first == "anthropic-skills:docx")
    }

    @Test func highlightIndicesCoverMatchedCharacters() {
        let match = SlashCommandMatcher.match(query: "uft", in: catalog, limit: 5).first
        #expect(match?.highlight == [7, 8, 9])
        let prefix = SlashCommandMatcher.match(query: "com", in: catalog, limit: 1).first
        #expect(prefix?.highlight == [0, 1, 2])
    }

    @Test func noMatchReturnsEmpty() {
        #expect(names("zzzz").isEmpty)
    }
}
