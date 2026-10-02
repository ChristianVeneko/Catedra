import Foundation

/// Looks for the tools the app depends on, running bounded commands through the login-shell environment.
struct DependencyProbe: DependencyProbing {
    var environment: @Sendable () -> [String: String] = { LoginShellEnvironment.childEnvironment() }

    func observe(_ id: DependencyID, context: DependencyProbeContext) async -> DependencyObservation {
        await Task.detached(priority: .userInitiated) { observeBlocking(id, context: context) }.value
    }

    func observeBlocking(_ id: DependencyID, context: DependencyProbeContext) -> DependencyObservation {
        switch id {
        case .python: return python(context)
        case .requests: return requests(context)
        case .git: return tool("git", args: ["--version"], needsCommandLineTools: true)
        case .node: return tool("node", args: ["--version"], needsCommandLineTools: false)
        case .agent(let provider): return agent(provider, override: context.agentPaths[provider])
        }
    }

    // MARK: Python

    /// The interpreter to use: the configured one, else the best of the usual locations (>= 3.9 with `requests` first).
    private func python(_ context: DependencyProbeContext) -> DependencyObservation {
        var paths: [String] = []
        if !context.pythonPath.isEmpty { paths.append(context.pythonPath) }
        if let found = BoundedProcess.which("python3") { paths.append(found) }
        paths += PythonLocator.candidates
        var seen = Set<String>()
        let usable = paths.filter { seen.insert($0).inserted && FileManager.default.isExecutableFile(atPath: $0) && isRunnable($0) }
        guard !usable.isEmpty else { return .notFound }
        var fallback: (path: String, output: String?)?
        var meetsMinimum: (path: String, output: String?)?
        for path in usable {
            let output = BoundedProcess.run(path, ["--version"], environment: environment())?.output
            let version = output.flatMap(SemanticVersion.parse)
            if fallback == nil { fallback = (path, output) }
            guard let version, version >= DependencyPlan.minimumPython else { continue }
            if meetsMinimum == nil { meetsMinimum = (path, output) }
            if hasRequests(path) != nil { return .found(path: path, output: output) }
        }
        let best = meetsMinimum ?? fallback
        return best.map { .found(path: $0.path, output: $0.output) } ?? .notFound
    }

    private func requests(_ context: DependencyProbeContext) -> DependencyObservation {
        guard !context.pythonPath.isEmpty else { return .failed("Requiere Python 3.") }
        if let version = hasRequests(context.pythonPath) { return .found(path: context.pythonPath, output: version) }
        return .notFound
    }

    private func hasRequests(_ python: String) -> String? {
        guard let result = BoundedProcess.run(python, ["-c", "import requests; print(requests.__version__)"],
                                              environment: environment(), timeout: 15), result.status == 0 else { return nil }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    // MARK: Other tools

    private func agent(_ provider: AgentProviderID, override: String?) -> DependencyObservation {
        guard let path = BinaryLocator(provider: provider).locate(override: override) else { return .notFound }
        return .found(path: path, output: AgentBinaryProbe().version(of: path))
    }

    private func tool(_ name: String, args: [String], needsCommandLineTools: Bool) -> DependencyObservation {
        guard let path = BoundedProcess.which(name), isRunnable(path) else { return .notFound }
        let output = BoundedProcess.run(path, args, environment: environment())?.output
        return .found(path: path, output: output)
    }

    /// `/usr/bin/{git,python3}` are shims that pop up the Command Line Tools installer when the tools are absent;
    /// never execute them in that case.
    private func isRunnable(_ path: String) -> Bool {
        guard path.hasPrefix("/usr/bin/") else { return true }
        return BoundedProcess.run("/usr/bin/xcode-select", ["-p"], timeout: 5)?.status == 0
    }
}
