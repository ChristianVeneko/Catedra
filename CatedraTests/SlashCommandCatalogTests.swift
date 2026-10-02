import Testing
import Foundation
@testable import Catedra

struct SlashCommandCatalogTests {
    private func cmd(_ name: String, kind: SlashCommand.Kind = .skill, aliases: [String] = []) -> SlashCommand {
        SlashCommand(name: name, description: "d", argumentHint: nil, aliases: aliases, kind: kind)
    }

    @Test func mergeDropsCliCommandsOverriddenByAppAndTerminalOnly() {
        let cli = [cmd("clear", kind: .builtin, aliases: ["reset", "new"]), cmd("model", kind: .builtin), cmd("compact", kind: .builtin),
                   cmd("doctor", kind: .builtin), cmd("normas-uft"), cmd("resume", kind: .builtin)]
        let merged = SlashCommandCatalogPolicy.merge(app: AppCommand.definitions, cli: cli, local: [])
        let names = merged.map(\.name)
        #expect(names.filter { $0 == "clear" }.isEmpty)
        #expect(!names.contains("doctor"))
        #expect(names.contains("compact") && names.contains("normas-uft"))
        #expect(names.filter { $0 == "model" }.count == 1)
        #expect(merged.first { $0.name == "model" }?.kind == .app)
    }

    @Test func mergeAddsLocalOnlyWhenMissingFromCli() {
        let merged = SlashCommandCatalogPolicy.merge(app: [], cli: [cmd("a")], local: [cmd("a"), cmd("b")])
        #expect(merged.map(\.name).sorted() == ["a", "b"])
    }

    @Test func grouping() {
        let sections = SlashCommandCatalogPolicy.sections(from: [cmd("s"), cmd("b", kind: .builtin), AppCommand.definitions[0]].map { SlashCommandMatch(command: $0, score: 0, highlight: []) })
        #expect(sections.map(\.title) == ["Cátedra", "Skills", "Comandos de Claude Code"])
    }

    @Test func storeRoundTrip() throws {
        let dir = try makeTempDirectory()
        let store = JSONSlashCommandCatalogStore(file: dir.appendingPathComponent("slash-commands.json"))
        #expect(store.load().isEmpty)
        let commands = [SlashCommand(name: "x", description: "desc", argumentHint: "[a]", aliases: ["y"], kind: .builtin), cmd("z")]
        try store.save(commands)
        #expect(store.load() == commands)
    }

    @Test func corruptCacheLoadsEmpty() throws {
        let dir = try makeTempDirectory()
        let file = dir.appendingPathComponent("slash-commands.json")
        try Data("nope".utf8).write(to: file)
        #expect(JSONSlashCommandCatalogStore(file: file).load().isEmpty)
    }
}
