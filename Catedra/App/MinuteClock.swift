import Foundation
import Observation

/// Publishes the current time, updating once per minute; drives the menu bar label.
@Observable @MainActor
final class MinuteClock {
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let current = Date()
        if Int(current.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) { now = current }
    }
}
