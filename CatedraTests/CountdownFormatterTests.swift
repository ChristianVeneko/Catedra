import Testing
import Foundation
@testable import Catedra

struct CountdownFormatterTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func daysAndHours() {
        #expect(CountdownFormatter.text(until: now.addingTimeInterval(31 * 3600 + 120), from: now) == "1 d 7 h")
    }
    @Test func hoursAndMinutes() {
        #expect(CountdownFormatter.text(until: now.addingTimeInterval(3 * 3600 + 12 * 60 + 30), from: now) == "3 h 12 min")
    }
    @Test func minutesOnly() {
        #expect(CountdownFormatter.text(until: now.addingTimeInterval(45 * 60), from: now) == "45 min")
    }
    @Test func lessThanAMinute() {
        #expect(CountdownFormatter.text(until: now.addingTimeInterval(20), from: now) == "Menos de 1 min")
    }
    @Test func overdue() {
        #expect(CountdownFormatter.text(until: now.addingTimeInterval(-1), from: now) == "Vencida")
    }
    @Test func exactDays() {
        #expect(CountdownFormatter.text(until: now.addingTimeInterval(2 * 86400), from: now) == "2 d 0 h")
    }
}
