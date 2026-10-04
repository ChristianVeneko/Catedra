import Foundation

/// A child process Cátedra launched and still waits for.
enum TrackedProcessKey: Hashable, Sendable {
    case agent(UUID)
    case sync
}

struct TrackedProcess: Equatable, Sendable {
    let key: TrackedProcessKey
    let pid: Int32
}

/// Adapters that launch child processes report them here.
protocol ChildProcessTracking: Sendable {
    func didStart(_ key: TrackedProcessKey, pid: Int32)
    func didExit(_ key: TrackedProcessKey)
}

protocol RunningProcessListing: Sendable {
    func runningProcesses() -> [TrackedProcess]
}

protocol ProcessSampling: Sendable {
    /// Snapshot of `rootPID` and all its descendants; empty when the root is gone.
    func snapshot(tree rootPID: Int32) -> [ProcessSnapshot]
}

protocol DiskUsageScanning: Sendable {
    /// Allocated size of every course folder under the workspace root. Blocking; call off the main thread.
    func scan(root: URL) -> [CourseDiskUsage]
}
