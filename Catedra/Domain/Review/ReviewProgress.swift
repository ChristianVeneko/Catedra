import Foundation

struct ReviewSettings: Equatable, Codable, Sendable {
    static let defaultNewCardsPerDay = 20
    static let maxNewCardsPerDay = 200

    /// New cards introduced per day and per deck.
    var newCardsPerDay: Int = ReviewSettings.defaultNewCardsPerDay

    var clampedNewCardsPerDay: Int { min(max(newCardsPerDay, 0), Self.maxNewCardsPerDay) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        newCardsPerDay = (try? c.decodeIfPresent(Int.self, forKey: .newCardsPerDay)) ?? Self.defaultNewCardsPerDay
    }

    private enum CodingKeys: String, CodingKey { case newCardsPerDay }
}

/// Everything stored in `review-progress.json`: settings plus per-course card progress.
struct ReviewProgressFile: Equatable, Codable, Sendable {
    var settings = ReviewSettings()
    /// Course folder name -> card id -> progress.
    var courses: [String: [String: CardProgress]] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey { case settings, courses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(ReviewSettings.self, forKey: .settings)) ?? ReviewSettings()
        let raw = (try? c.decodeIfPresent([String: Lossy<[String: Lossy<CardProgress>]>].self, forKey: .courses)) ?? [:]
        for (course, entries) in raw {
            guard let entries = entries.value else { continue }
            courses[course] = entries.compactMapValues(\.value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(settings, forKey: .settings)
        try c.encode(courses, forKey: .courses)
    }

    /// Decodes one element, yielding nil instead of failing the whole file.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}
