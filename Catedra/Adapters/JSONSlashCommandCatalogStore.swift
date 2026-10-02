import Foundation

/// Persists the latest CLI command catalog to `~/Library/Application Support/Catedra/slash-commands.json`.
struct JSONSlashCommandCatalogStore: SlashCommandCatalogStoring {
    private struct Payload: Codable { let updatedAt: Date; let commands: [SlashCommand] }

    let file: URL

    init(file: URL = JSONSlashCommandCatalogStore.defaultFile) { self.file = file }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catedra/slash-commands.json")
    }

    func load() -> [SlashCommand] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file), let payload = try? decoder.decode(Payload.self, from: data) else { return [] }
        return payload.commands
    }

    func save(_ commands: [SlashCommand]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Payload(updatedAt: .now, commands: commands)).write(to: file, options: .atomic)
    }
}
