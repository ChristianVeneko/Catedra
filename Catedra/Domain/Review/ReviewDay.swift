import Foundation

/// A calendar day in America/Caracas, counted from 1970-01-01. Spaced-repetition due dates are whole days, so a card
/// reviewed at 11 p.m. and one reviewed at 8 a.m. are due on the same day.
struct ReviewDay: Comparable, Hashable, Sendable, Codable, CustomStringConvertible {
    static let timeZone = TimeZone(identifier: "America/Caracas")!

    let index: Int

    init(index: Int) { self.index = index }

    init(date: Date, timeZone: TimeZone = ReviewDay.timeZone) {
        let local = Int(date.timeIntervalSince1970.rounded(.down)) + timeZone.secondsFromGMT(for: date)
        self.index = Int((Double(local) / 86_400).rounded(.down))
    }

    /// Parses `yyyy-MM-dd`.
    init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let days = Self.daysFromCivil(year: y, month: m, day: d)
        guard Self.civil(fromDays: days) == (y, m, d) else { return nil } // rejects 2026-02-31 and similar
        self.index = days
    }

    func adding(days: Int) -> ReviewDay { ReviewDay(index: index + days) }

    var description: String {
        let (y, m, d) = Self.civil(fromDays: index)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func < (lhs: ReviewDay, rhs: ReviewDay) -> Bool { lhs.index < rhs.index }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = ReviewDay(string: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid day \(text)"))
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    // Howard Hinnant's civil-date algorithms (proleptic Gregorian).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civil(fromDays days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}
