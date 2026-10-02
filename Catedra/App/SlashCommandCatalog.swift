import Foundation
import Observation

/// Source of truth for the composer's slash commands, per provider: cached CLI catalog (Claude only) + local scan +
/// app commands.
@Observable @MainActor
final class SlashCommandCatalog {
    private(set) var cliCommands: [AgentProviderID: [SlashCommand]]
    private(set) var hasFullCatalog: [AgentProviderID: Bool]
    private var scanned: [String: [SlashCommand]] = [:]
    private var scanning: Set<String> = []

    private let store: SlashCommandCatalogStoring
    private let scanners: [AgentProviderID: SlashCommandScanning]

    /// `store` caches the Claude catalog (the only provider that reports one on its stream).
    init(store: SlashCommandCatalogStoring, scanners: [AgentProviderID: SlashCommandScanning]) {
        self.store = store
        self.scanners = scanners
        let cached = store.load()
        self.cliCommands = cached.isEmpty ? [:] : [.claude: cached]
        self.hasFullCatalog = [.claude: !cached.isEmpty]
    }

    private func key(_ folder: URL, _ provider: AgentProviderID) -> String { "\(provider.rawValue)|\(folder.path)" }

    /// Commands for the popup in a working folder.
    func commands(in folder: URL, provider: AgentProviderID) -> [SlashCommand] {
        SlashCommandCatalogPolicy.merge(app: AppCommand.definitions(for: provider), cli: cliCommands[provider] ?? [],
                                        local: scanned[key(folder, provider)] ?? [], provider: provider)
    }

    /// Names of the provider's own commands (not the app's), used to decide whether `/name` is a real command.
    func providerCommandNames(in folder: URL, provider: AgentProviderID) -> Set<String> {
        Set(((cliCommands[provider] ?? []) + (scanned[key(folder, provider)] ?? [])).map(\.name))
    }

    /// Scans the folder's commands on a background queue once (cheap, no tokens).
    func prepare(folder: URL, provider: AgentProviderID) async {
        let id = key(folder, provider)
        guard let scanner = scanners[provider], scanned[id] == nil, scanning.insert(id).inserted else { return }
        let found = await Task.detached { scanner.scan(folder: folder) }.value
        scanned[id] = found
        scanning.remove(id)
    }

    /// Called with every catalog a run reports. A names-only catalog never replaces a full one.
    func ingest(_ commands: [SlashCommand], complete: Bool, provider: AgentProviderID = .claude) {
        guard !commands.isEmpty else { return }
        if !complete && hasFullCatalog[provider] == true { return }
        guard commands != cliCommands[provider] else { return }
        cliCommands[provider] = commands
        hasFullCatalog[provider] = complete
        guard complete, provider == .claude else { return }
        let store = self.store
        Task.detached { try? store.save(commands) }
    }
}
