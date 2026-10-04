import Foundation

/// CPU time and resident memory of one process at one instant. `startTime` disambiguates reused pids.
struct ProcessSnapshot: Equatable, Sendable {
    let pid: Int32
    let startTime: UInt64
    let cpuSeconds: Double
    let rssBytes: UInt64
}

/// CPU % of a process tree between consecutive samples: delta of total CPU time over wall time (100 = one full core).
struct CPUDeltaCalculator: Sendable {
    private struct Identity: Hashable { let pid: Int32; let startTime: UInt64 }
    private var previous: [Identity: Double] = [:]
    private var lastDate: Date?

    mutating func update(_ snapshots: [ProcessSnapshot], at date: Date) -> Double {
        let current = Dictionary(snapshots.map { (Identity(pid: $0.pid, startTime: $0.startTime), $0.cpuSeconds) },
                                 uniquingKeysWith: { _, last in last })
        defer { previous = current; lastDate = date }
        guard let lastDate else { return 0 }
        let elapsed = date.timeIntervalSince(lastDate)
        guard elapsed > 0 else { return 0 }
        var delta = 0.0
        for (identity, cpu) in current {
            // A process we have not seen was born since the last sample: all its CPU time is new.
            delta += max(0, cpu - (previous[identity] ?? 0))
        }
        return delta / elapsed * 100
    }
}

/// Fixed-size window of the newest samples (sparkline data).
struct SampleHistory: Equatable, Sendable {
    let limit: Int
    private(set) var values: [Double] = []

    init(limit: Int = 30) { self.limit = max(1, limit) }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > limit { values.removeFirst(values.count - limit) }
    }
}

/// A live child process (with its descendants) to measure.
struct ResourceTarget: Equatable, Sendable {
    enum Kind: Sendable { case agent, sync }
    let id: String
    let pid: Int32
    let kind: Kind
    let label: String
    let provider: AgentProviderID?
    let scope: AgentScopeRef?
}

struct ResourceNode: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case course, scope, process, sync }
    let id: String
    let kind: Kind
    let title: String
    var subtitle: String?
    var provider: AgentProviderID?
    var cpu: Double
    var rss: UInt64
    var history: [Double] = []
    var children: [ResourceNode] = []
    /// Set on process leaves: what the "×" button stops.
    var processKey: TrackedProcessKey?
}

struct ResourceReport: Equatable, Sendable {
    var roots: [ResourceNode]
    var totalCPU: Double
    var totalRSS: UInt64
    static let empty = ResourceReport(roots: [], totalCPU: 0, totalRSS: 0)
}

enum ResourceTargetBuilder {
    /// Pairs tracked pids with the runs they belong to; agent pids whose run is unknown are ignored.
    static func targets(tracked: [TrackedProcess], runs: [AgentRun]) -> [ResourceTarget] {
        tracked.compactMap { process in
            switch process.key {
            case .sync:
                return ResourceTarget(id: "sync", pid: process.pid, kind: .sync, label: "Sincronización con SAIA",
                                      provider: nil, scope: nil)
            case .agent(let runID):
                guard let run = runs.first(where: { $0.id == runID }) else { return nil }
                return ResourceTarget(id: "run:\(runID.uuidString)", pid: process.pid, kind: .agent, label: run.title,
                                      provider: run.provider, scope: run.scope)
            }
        }
    }
}

/// Turns raw per-target snapshots into the course → scope → process tree with CPU deltas, sums and history.
struct ResourceAggregator: Sendable {
    private let historyLimit: Int
    private var calculators: [String: CPUDeltaCalculator] = [:]
    private var histories: [String: SampleHistory] = [:]

    init(historyLimit: Int = 30) { self.historyLimit = historyLimit }

    mutating func ingest(targets: [ResourceTarget], snapshots: [String: [ProcessSnapshot]], at date: Date) -> ResourceReport {
        var leaves: [(target: ResourceTarget, node: ResourceNode)] = []
        var live = Set<String>()
        for target in targets {
            guard let snaps = snapshots[target.id], !snaps.isEmpty else { continue }
            live.insert(target.id)
            var calculator = calculators[target.id] ?? CPUDeltaCalculator()
            let cpu = calculator.update(snaps, at: date)
            calculators[target.id] = calculator
            leaves.append((target, ResourceNode(
                id: target.id, kind: .process, title: target.provider?.displayName ?? "Sincronización", subtitle: target.label,
                provider: target.provider, cpu: cpu, rss: snaps.reduce(0) { $0 + $1.rssBytes },
                processKey: Self.key(for: target))))
        }
        calculators = calculators.filter { live.contains($0.key) }

        var roots: [ResourceNode] = []
        var courseOrder: [String] = []
        var byCourse: [String: [String: [ResourceNode]]] = [:] // course folder -> scope folder -> leaves
        var scopes: [String: AgentScopeRef] = [:]
        for (target, node) in leaves {
            guard let scope = target.scope else {
                roots.append(Self.group(id: "sync", kind: .sync, title: "Sincronización", children: [node]))
                continue
            }
            let course = scope.courseFolderName
            if byCourse[course] == nil { courseOrder.append(course) }
            byCourse[course, default: [:]][scope.folder, default: []].append(node)
            scopes[scope.folder] = scope
        }
        for course in courseOrder {
            let scopeNodes = (byCourse[course] ?? [:]).map { folder, nodes -> ResourceNode in
                let ref = scopes[folder]
                let title = ref?.kind == .course ? "Materia completa" : (ref?.title ?? folder)
                return Self.group(id: "scope:\(folder)", kind: .scope, title: title, children: nodes)
            }
            let name = Course(folderName: course)?.name ?? course
            roots.append(Self.group(id: "course:\(course)", kind: .course, title: name, children: scopeNodes))
        }
        roots.sort { ($0.rss, $1.title) > ($1.rss, $0.title) }

        roots = roots.map { recordHistory($0) }
        var seen = Set<String>()
        collectIDs(roots, into: &seen)
        histories = histories.filter { seen.contains($0.key) }
        return ResourceReport(roots: roots, totalCPU: roots.reduce(0) { $0 + $1.cpu }, totalRSS: roots.reduce(0) { $0 + $1.rss })
    }

    private static func key(for target: ResourceTarget) -> TrackedProcessKey? {
        switch target.kind {
        case .sync: .sync
        case .agent: UUID(uuidString: String(target.id.dropFirst("run:".count))).map(TrackedProcessKey.agent)
        }
    }

    private static func group(id: String, kind: ResourceNode.Kind, title: String, children: [ResourceNode]) -> ResourceNode {
        let sorted = children.sorted { ($0.rss, $1.title) > ($1.rss, $0.title) }
        return ResourceNode(id: id, kind: kind, title: title, cpu: sorted.reduce(0) { $0 + $1.cpu },
                            rss: sorted.reduce(0) { $0 + $1.rss }, children: sorted)
    }

    private mutating func recordHistory(_ node: ResourceNode) -> ResourceNode {
        var node = node
        var history = histories[node.id] ?? SampleHistory(limit: historyLimit)
        history.append(node.cpu)
        histories[node.id] = history
        node.history = history.values
        node.children = node.children.map { recordHistory($0) }
        return node
    }

    private func collectIDs(_ nodes: [ResourceNode], into set: inout Set<String>) {
        for node in nodes { set.insert(node.id); collectIDs(node.children, into: &set) }
    }
}

enum ResourceFormatter {
    /// "512 MB" below one gigabyte, "2.55 GB" above (binary units, locale independent).
    static func bytes(_ value: UInt64) -> String {
        let mb = Double(value) / 1_048_576
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    static func cpu(_ percent: Double) -> String { String(format: "%.1f%%", percent) }
}
