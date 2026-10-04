import Foundation

/// Thread-safe list of the child processes Cátedra launched and is still waiting for.
final class ChildProcessRegistry: ChildProcessTracking, RunningProcessListing, @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [TrackedProcessKey: Int32] = [:]

    func didStart(_ key: TrackedProcessKey, pid: Int32) {
        lock.lock(); pids[key] = pid; lock.unlock()
    }

    func didExit(_ key: TrackedProcessKey) {
        lock.lock(); pids[key] = nil; lock.unlock()
    }

    func runningProcesses() -> [TrackedProcess] {
        lock.lock(); defer { lock.unlock() }
        return pids.map { TrackedProcess(key: $0.key, pid: $0.value) }
    }
}
