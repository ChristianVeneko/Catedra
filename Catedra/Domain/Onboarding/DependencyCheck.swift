import Foundation

enum DependencyID: Hashable, Sendable {
    case python, requests, git, node
    case agent(AgentProviderID)
}

enum DependencyRequirement: Sendable, Equatable { case required, optional }

enum DependencyStatus: Sendable, Equatable {
    case checking
    case ok
    case missing
    case outdated(found: String, minimum: String)
}

/// What a probe saw on this machine for one dependency.
enum DependencyObservation: Sendable, Equatable {
    case notFound
    /// `output` is the raw version text (`--version`, `import requests; print(requests.__version__)`).
    case found(path: String?, output: String?)
    case failed(String)
}

/// What the app needs and how to obtain it.
struct DependencySpec: Sendable, Equatable {
    var id: DependencyID
    var name: String
    var requirement: DependencyRequirement
    var minimumVersion: SemanticVersion?
    var installCommand: String?
    /// True when `installCommand` is a shell command (copyable); false for a plain instruction.
    var installIsCommand = true
    var note: String?

    init(id: DependencyID, name: String, requirement: DependencyRequirement, minimumVersion: SemanticVersion? = nil,
         installCommand: String? = nil, installIsCommand: Bool = true, note: String? = nil) {
        self.id = id; self.name = name; self.requirement = requirement; self.minimumVersion = minimumVersion
        self.installCommand = installCommand; self.installIsCommand = installIsCommand; self.note = note
    }
}

/// Evaluated state of one dependency row in the setup checklist.
struct DependencyCheck: Identifiable, Sendable, Equatable {
    var id: DependencyID
    var name: String
    var requirement: DependencyRequirement
    var status: DependencyStatus
    var version: String?
    var detail: String?
    var installCommand: String?
    var installIsCommand = true
    var note: String?

    init(id: DependencyID, name: String, requirement: DependencyRequirement, status: DependencyStatus,
         version: String? = nil, detail: String? = nil, installCommand: String? = nil, installIsCommand: Bool = true, note: String? = nil) {
        self.id = id; self.name = name; self.requirement = requirement; self.status = status; self.version = version
        self.detail = detail; self.installCommand = installCommand; self.installIsCommand = installIsCommand; self.note = note
    }

    /// A required dependency that is not satisfied.
    var blocksReadiness: Bool {
        guard requirement == .required else { return false }
        if case .ok = status { return false }
        if case .checking = status { return false }
        return true
    }
}

enum DependencyReadiness: Sendable, Equatable {
    case ready
    case checking
    case blocked([DependencyID])
}

enum DependencyEvaluator {
    static func evaluate(_ spec: DependencySpec, _ observation: DependencyObservation) -> DependencyCheck {
        var check = DependencyCheck(id: spec.id, name: spec.name, requirement: spec.requirement, status: .missing,
                                    installCommand: spec.installCommand, installIsCommand: spec.installIsCommand, note: spec.note)
        switch observation {
        case .notFound:
            check.status = .missing
        case .failed(let reason):
            check.status = .missing
            check.detail = reason
        case .found(let path, let output):
            let version = output.flatMap(SemanticVersion.parse)
            check.version = version?.description
            check.detail = path
            if let minimum = spec.minimumVersion, (version ?? SemanticVersion(0)) < minimum {
                check.status = .outdated(found: version?.description ?? "desconocida", minimum: minimum.description)
            } else {
                check.status = .ok
            }
        }
        return check
    }

    static func readiness(_ checks: [DependencyCheck]) -> DependencyReadiness {
        let blocking = checks.filter(\.blocksReadiness).map(\.id)
        if !blocking.isEmpty { return .blocked(blocking) }
        let pendingRequired = checks.contains { $0.requirement == .required && $0.status == .checking }
        return pendingRequired ? .checking : .ready
    }
}

enum DependencyPlan {
    static let minimumPython = SemanticVersion(3, 9)
    static let requestsInstallCommand = "python3 -m pip install --user requests"

    /// Everything the setup checks: the selected agent is required, the other agents and dev tools are optional.
    static func specs(selectedAgent: AgentProviderID) -> [DependencySpec] {
        var specs = [
            DependencySpec(id: .python, name: "Python 3", requirement: .required, minimumVersion: minimumPython,
                           installCommand: "brew install python", note: "Versión 3.9 o superior; ejecuta el script de sincronización."),
            DependencySpec(id: .requests, name: "Módulo «requests»", requirement: .required,
                           installCommand: requestsInstallCommand, note: "Biblioteca de Python que usa el script para hablar con SAIA."),
        ]
        let agents = [selectedAgent] + AgentProviderID.allCases.filter { $0 != selectedAgent }
        for agent in agents {
            specs.append(DependencySpec(id: .agent(agent), name: agent.displayName,
                                        requirement: agent == selectedAgent ? .required : .optional,
                                        installCommand: agent.installHint, installIsCommand: agent.installHintIsCommand))
        }
        specs.append(DependencySpec(id: .git, name: "Git", requirement: .optional, installCommand: "xcode-select --install",
                                    note: "Solo informativo."))
        specs.append(DependencySpec(id: .node, name: "Node.js", requirement: .optional, installCommand: "brew install node",
                                    note: "Solo informativo."))
        return specs
    }
}
