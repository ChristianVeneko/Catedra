import Foundation
import Observation

/// Source of truth for the composer's slash commands: cached CLI catalog + local scan + app commands.
@Observable @MainActor
final class SlashCommandCatalog {
    private(set) var cliCommands: [SlashCommand]
    private(set) var hasFullCatalog: Bool
    private var scanned: [String: [SlashCommand]] = [:]
    private var scanning: Set<String> = []

    private let store: SlashCommandCatalogStoring
    private let scanner: SlashCommandScanning

    init(store: SlashCommandCatalogStoring, scanner: SlashCommandScanning) {
        self.store = store
        self.scanner = scanner
        let cached = store.load()
        self.cliCommands = cached
        self.hasFullCatalog = !cached.isEmpty
    }

    /// Commands for the popup in a working folder.
    func commands(in folder: URL) -> [SlashCommand] {
        SlashCommandCatalogPolicy.merge(app: AppCommand.definitions, cli: cliCommands, local: scanned[folder.path] ?? [])
    }

    /// Scans the folder's skills on a background queue once (cheap, no tokens).
    func prepare(folder: URL) async {
        let key = folder.path
        guard scanned[key] == nil, scanning.insert(key).inserted else { return }
        let scanner = self.scanner
        let found = await Task.detached { scanner.scan(folder: folder) }.value
        scanned[key] = found
        scanning.remove(key)
    }

    /// Called with every catalog a run reports. A names-only catalog never replaces a full one.
    func ingest(_ commands: [SlashCommand], complete: Bool) {
        guard !commands.isEmpty else { return }
        if !complete && hasFullCatalog { return }
        guard commands != cliCommands else { return }
        cliCommands = commands
        hasFullCatalog = complete
        guard complete else { return }
        let store = self.store
        Task.detached { try? store.save(commands) }
    }
}
