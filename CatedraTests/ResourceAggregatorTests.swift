import Testing
import Foundation
@testable import Catedra

struct ResourceAggregatorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let courseA = "08 - Teoria de Control II"
    private let courseB = "03 - Fisica"

    private func scope(_ kind: AgentScopeKind, _ folder: String, _ title: String) -> AgentScopeRef {
        AgentScopeRef(kind: kind, folder: folder, title: title)
    }
    private func target(_ n: Int, scope: AgentScopeRef, provider: AgentProviderID = .claude, label: String = "Tarea") -> ResourceTarget {
        ResourceTarget(id: "run:\(n)", pid: Int32(100 + n), kind: .agent, label: label, provider: provider, scope: scope)
    }
    private func snap(_ pid: Int32, cpu: Double, rss: UInt64) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, startTime: 1, cpuSeconds: cpu, rssBytes: rss)
    }

    @Test func groupsCourseScopeProcessAndSums() {
        let act = scope(.activity, "\(courseA)/actividades/Tarea 1", "Tarea 1")
        let whole = scope(.course, courseA, "Teoria")
        let other = scope(.activity, "\(courseB)/actividades/Lab", "Lab")
        let targets = [target(1, scope: act), target(2, scope: act), target(3, scope: whole), target(4, scope: other)]
        var agg = ResourceAggregator()
        let snaps: [String: [ProcessSnapshot]] = [
            "run:1": [snap(101, cpu: 1, rss: 100), snap(201, cpu: 1, rss: 50)],
            "run:2": [snap(102, cpu: 1, rss: 200)],
            "run:3": [snap(103, cpu: 1, rss: 400)],
            "run:4": [snap(104, cpu: 1, rss: 1_000)],
        ]
        let report = agg.ingest(targets: targets, snapshots: snaps, at: t0)
        #expect(report.roots.count == 2)
        // Sorted by RSS descending: course B (1000) before course A (750).
        #expect(report.roots.map(\.id) == ["course:\(courseB)", "course:\(courseA)"])
        let a = report.roots[1]
        #expect(a.title == "Teoria de Control II")
        #expect(a.kind == .course)
        #expect(a.rss == 750)
        #expect(a.children.count == 2)
        let actNode = a.children.first { $0.id == "scope:\(act.folder)" }
        #expect(actNode?.rss == 350)
        #expect(actNode?.title == "Tarea 1")
        #expect(actNode?.children.map(\.id).sorted() == ["run:1", "run:2"])
        let wholeNode = a.children.first { $0.id == "scope:\(whole.folder)" }
        #expect(wholeNode?.title == "Materia completa")
        #expect(report.totalRSS == 1_750)
    }

    @Test func leafCarriesProviderAndLabel() throws {
        let act = scope(.activity, "\(courseA)/actividades/T", "T")
        var agg = ResourceAggregator()
        let report = agg.ingest(targets: [target(1, scope: act, provider: .opencode, label: "Resumen")],
                                snapshots: ["run:1": [snap(101, cpu: 0, rss: 10)]], at: t0)
        let leaf = try #require(report.roots.first?.children.first?.children.first)
        #expect(leaf.kind == .process)
        #expect(leaf.provider == .opencode)
        #expect(leaf.title == "OpenCode")
        #expect(leaf.subtitle == "Resumen")
    }

    @Test func syncIsItsOwnTopLevelGroup() throws {
        let sync = ResourceTarget(id: "sync", pid: 500, kind: .sync, label: "Sincronización con SAIA", provider: nil, scope: nil)
        var agg = ResourceAggregator()
        let report = agg.ingest(targets: [sync], snapshots: ["sync": [snap(500, cpu: 0, rss: 64)]], at: t0)
        let root = try #require(report.roots.first)
        #expect(root.kind == .sync)
        #expect(root.title == "Sincronización")
        #expect(root.rss == 64)
        #expect(root.children.map(\.id) == ["sync"])
        #expect(root.children.first?.kind == .process)
    }

    @Test func targetsWithoutSnapshotsAreDropped() {
        let act = scope(.activity, "\(courseA)/a/T", "T")
        var agg = ResourceAggregator()
        let report = agg.ingest(targets: [target(1, scope: act)], snapshots: ["run:1": []], at: t0)
        #expect(report.roots.isEmpty)
        #expect(report.totalRSS == 0)
    }

    @Test func cpuUsesDeltaAndGroupsSumChildren() throws {
        let act = scope(.activity, "\(courseA)/a/T", "T")
        let targets = [target(1, scope: act), target(2, scope: act)]
        var agg = ResourceAggregator()
        _ = agg.ingest(targets: targets, snapshots: ["run:1": [snap(101, cpu: 1, rss: 1)], "run:2": [snap(102, cpu: 1, rss: 1)]], at: t0)
        let report = agg.ingest(targets: targets,
                                snapshots: ["run:1": [snap(101, cpu: 2, rss: 1)], "run:2": [snap(102, cpu: 1.5, rss: 1)]],
                                at: t0.addingTimeInterval(2))
        let course = try #require(report.roots.first)
        #expect(abs(course.cpu - 75) < 0.001)
        #expect(abs(report.totalCPU - 75) < 0.001)
        let leaves = course.children[0].children
        #expect(abs((leaves.first { $0.id == "run:1" }?.cpu ?? -1) - 50) < 0.001)
    }

    @Test func historyIsKeptPerNodeAndCapped() throws {
        let act = scope(.activity, "\(courseA)/a/T", "T")
        let t = [target(1, scope: act)]
        var agg = ResourceAggregator(historyLimit: 3)
        var report = ResourceReport.empty
        for i in 0..<5 {
            report = agg.ingest(targets: t, snapshots: ["run:1": [snap(101, cpu: Double(i), rss: 1)]],
                                at: t0.addingTimeInterval(Double(i)))
        }
        let course = try #require(report.roots.first)
        #expect(course.history.count == 3)
        #expect(course.children[0].children[0].history.count == 3)
        // cpu per step = 1 s / 1 s = 100%; first sample was 0 and has been trimmed away.
        #expect(course.history == [100, 100, 100])
    }

    @Test func historyForVanishedNodesIsForgotten() throws {
        let act = scope(.activity, "\(courseA)/a/T", "T")
        let t = [target(1, scope: act)]
        var agg = ResourceAggregator()
        _ = agg.ingest(targets: t, snapshots: ["run:1": [snap(101, cpu: 0, rss: 1)]], at: t0)
        _ = agg.ingest(targets: [], snapshots: [:], at: t0.addingTimeInterval(2))
        let back = agg.ingest(targets: t, snapshots: ["run:1": [snap(101, cpu: 0, rss: 1)]], at: t0.addingTimeInterval(4))
        #expect(back.roots.first?.history.count == 1)
    }
}

struct SampleHistoryTests {
    @Test func capsAtLimitKeepingNewest() {
        var h = SampleHistory(limit: 3)
        for v in 1...5 { h.append(Double(v)) }
        #expect(h.values == [3, 4, 5])
    }
    @Test func defaultLimitIs30() {
        var h = SampleHistory()
        for v in 0..<40 { h.append(Double(v)) }
        #expect(h.values.count == 30)
        #expect(h.values.first == 10)
    }
}

struct ResourceTargetBuilderTests {
    @Test func mapsTrackedProcessesToRunsAndSync() {
        let ref = AgentScopeRef(kind: .activity, folder: "08 - X/a/T", title: "T")
        var run = AgentRun(provider: .claude, scope: ref, prompt: "Haz un resumen\nlargo", recipeID: nil, recipeTitle: nil, at: .now)
        run.status = .running
        let unknown = UUID()
        let tracked = [TrackedProcess(key: .agent(run.id), pid: 7), TrackedProcess(key: .agent(unknown), pid: 8),
                       TrackedProcess(key: .sync, pid: 9)]
        let targets = ResourceTargetBuilder.targets(tracked: tracked, runs: [run])
        #expect(targets.count == 2)
        #expect(targets[0].id == "run:\(run.id.uuidString)")
        #expect(targets[0].pid == 7)
        #expect(targets[0].label == "Haz un resumen")
        #expect(targets[0].scope == ref)
        #expect(targets[1].kind == .sync)
        #expect(targets[1].pid == 9)
    }
}
