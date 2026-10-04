import Testing
import Foundation
@testable import Catedra

struct CPUDeltaCalculatorTests {
    private func snap(_ pid: Int32, start: UInt64 = 1, cpu: Double, rss: UInt64 = 0) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, startTime: start, cpuSeconds: cpu, rssBytes: rss)
    }
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func firstSampleIsZero() {
        var calc = CPUDeltaCalculator()
        #expect(calc.update([snap(10, cpu: 5)], at: t0) == 0)
    }

    @Test func deltaOverWallTime() {
        var calc = CPUDeltaCalculator()
        _ = calc.update([snap(10, cpu: 5)], at: t0)
        let pct = calc.update([snap(10, cpu: 6.5)], at: t0.addingTimeInterval(2))
        #expect(abs(pct - 75) < 0.001)
    }

    @Test func sumsAcrossProcessesAndCanExceed100() {
        var calc = CPUDeltaCalculator()
        _ = calc.update([snap(10, cpu: 1), snap(11, cpu: 1)], at: t0)
        let pct = calc.update([snap(10, cpu: 3), snap(11, cpu: 3)], at: t0.addingTimeInterval(2))
        #expect(abs(pct - 200) < 0.001)
    }

    @Test func newDescendantCountsItsWholeCPUTime() {
        var calc = CPUDeltaCalculator()
        _ = calc.update([snap(10, cpu: 1)], at: t0)
        let pct = calc.update([snap(10, cpu: 1), snap(12, cpu: 1)], at: t0.addingTimeInterval(2))
        #expect(abs(pct - 50) < 0.001)
    }

    @Test func disappearedProcessNeverGoesNegative() {
        var calc = CPUDeltaCalculator()
        _ = calc.update([snap(10, cpu: 1), snap(11, cpu: 9)], at: t0)
        let pct = calc.update([snap(10, cpu: 2)], at: t0.addingTimeInterval(2))
        #expect(abs(pct - 50) < 0.001)
    }

    @Test func reusedPIDWithDifferentStartTimeIsANewProcess() {
        var calc = CPUDeltaCalculator()
        _ = calc.update([snap(10, start: 1, cpu: 100)], at: t0)
        // Same pid, new start time and a lower counter: not a negative delta against the old process.
        let pct = calc.update([snap(10, start: 2, cpu: 0.5)], at: t0.addingTimeInterval(1))
        #expect(abs(pct - 50) < 0.001)
    }

    @Test func nonAdvancingClockYieldsZero() {
        var calc = CPUDeltaCalculator()
        _ = calc.update([snap(10, cpu: 1)], at: t0)
        #expect(calc.update([snap(10, cpu: 2)], at: t0) == 0)
    }
}
