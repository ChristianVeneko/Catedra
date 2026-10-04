import Foundation
import Observation

/// Samples the agent and sync process trees and runs the disk scan. Full samples (tree + sparkline history) only while the
/// popover is visible; otherwise a cheaper pass keeps just the total for the toolbar indicator.
@Observable @MainActor
final class ResourceMonitorModel {
    enum DiskState: Equatable {
        case idle, scanning
        case scanned(DiskUsageSummary, at: Date)
    }

    private(set) var report = ResourceReport.empty
    private(set) var indicatorRSS: UInt64 = 0
    private(set) var disk: DiskState = .idle
    var isVisible = false {
        didSet { if isVisible, !oldValue { Task { await sample() } } }
    }

    private let sampler: ProcessSampling
    private let processes: RunningProcessListing
    private let scanner: DiskUsageScanning
    private let runs: @MainActor () -> [AgentRun]
    private let workspaceRoot: @MainActor () -> URL
    private var aggregator = ResourceAggregator()
    private var loop: Task<Void, Never>?

    static let visibleInterval: Duration = .seconds(2)
    static let hiddenInterval: Duration = .seconds(5)

    init(sampler: ProcessSampling, processes: RunningProcessListing, scanner: DiskUsageScanning,
         runs: @escaping @MainActor () -> [AgentRun], workspaceRoot: @escaping @MainActor () -> URL) {
        self.sampler = sampler
        self.processes = processes
        self.scanner = scanner
        self.runs = runs
        self.workspaceRoot = workspaceRoot
    }

    /// Starts the sampling loop once; it lives as long as the app.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sample()
                try? await Task.sleep(for: self.isVisible ? Self.visibleInterval : Self.hiddenInterval)
            }
        }
    }

    func sample() async {
        let targets = ResourceTargetBuilder.targets(tracked: processes.runningProcesses(), runs: runs())
        let sampler = self.sampler
        let snapshots = await Task.detached {
            Dictionary(uniqueKeysWithValues: targets.map { ($0.id, sampler.snapshot(tree: $0.pid)) })
        }.value
        if isVisible {
            report = aggregator.ingest(targets: targets, snapshots: snapshots, at: .now)
            indicatorRSS = report.totalRSS
        } else {
            indicatorRSS = snapshots.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.rssBytes } }
            if !report.roots.isEmpty { report = .empty; aggregator = ResourceAggregator() }
        }
    }

    func scanDisk() {
        guard disk != .scanning else { return }
        disk = .scanning
        let scanner = self.scanner
        let root = workspaceRoot()
        Task {
            let entries = await Task.detached(priority: .utility) { scanner.scan(root: root) }.value
            disk = .scanned(DiskUsageSummary(entries: entries), at: .now)
        }
    }
}
