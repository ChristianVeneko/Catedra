import Foundation

enum CountdownFormatter {
    /// Spanish compact countdown: "1 d 7 h", "3 h 12 min", "45 min", "Menos de 1 min", "Vencida".
    static func text(until due: Date, from now: Date) -> String {
        let seconds = due.timeIntervalSince(now)
        guard seconds >= 0 else { return "Vencida" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "Menos de 1 min"
    }
}
