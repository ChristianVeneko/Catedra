import Foundation

enum CancelSignal: Equatable, Sendable { case interrupt, terminate, kill }

/// Escalation used to stop a child agent: SIGINT ends the turn cleanly, SIGTERM (after a grace period) ends the run
/// and kills running tool process trees, SIGKILL is the last resort. Pure so the sequencing is unit-testable.
struct CancellationPolicy: Sendable, Equatable {
    var interruptGrace: TimeInterval = 4
    var terminateGrace: TimeInterval = 3

    /// Signal that should have been delivered `elapsed` seconds after cancellation was requested.
    func signal(afterElapsed elapsed: TimeInterval) -> CancelSignal {
        if elapsed >= interruptGrace + terminateGrace { return .kill }
        if elapsed >= interruptGrace { return .terminate }
        return .interrupt
    }

    /// Ordered steps: send `signal`, then wait up to `wait` seconds for the process to exit.
    var steps: [(signal: CancelSignal, wait: TimeInterval)] {
        [(.interrupt, interruptGrace), (.terminate, terminateGrace), (.kill, 0)]
    }
}
