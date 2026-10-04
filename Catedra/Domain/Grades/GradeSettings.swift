import Foundation

/// User choices about grades, stored in Application Support (never in the workspace).
struct GradeSettings: Equatable, Sendable, Codable {
    static let defaultTarget = 50.0

    /// Courses (folder names) the user merged into one subject.
    var groups: [[String]] = []
    /// Passing target in percent of the subject total, by subject id.
    var targets: [String: Double] = [:]
    /// Items marked "no cuenta" (`GradeLine.id`).
    var excludedItems: Set<String> = []
    /// Automatic grouping suggestions the user rejected (`SubjectGrouping.suggestionKey`).
    var dismissedSuggestions: Set<String> = []

    func target(forSubject id: String) -> Double { targets[id] ?? Self.defaultTarget }

    mutating func setTarget(_ percent: Double, forSubject id: String) {
        targets[id] = min(100, max(0, percent))
    }

    mutating func toggleExcluded(_ itemID: String) {
        if !excludedItems.insert(itemID).inserted { excludedItems.remove(itemID) }
    }

    /// Merges `keys` into one subject; the courses leave any previous group (groups left with fewer than two are dropped).
    mutating func group(_ keys: [String]) {
        guard keys.count >= 2 else { return }
        groups = groups.map { $0.filter { !keys.contains($0) } }.filter { $0.count >= 2 }
        groups.append(keys)
    }

    mutating func ungroup(_ key: String) {
        groups = groups.map { $0.filter { $0 != key } }.filter { $0.count >= 2 }
    }

    mutating func dismissSuggestion(_ keys: [String]) {
        dismissedSuggestions.insert(SubjectGrouping.suggestionKey(keys))
    }

    init() {}

    private enum CodingKeys: String, CodingKey { case groups, targets, excludedItems, dismissedSuggestions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = (try? c.decodeIfPresent([[String]].self, forKey: .groups)) ?? []
        targets = (try? c.decodeIfPresent([String: Double].self, forKey: .targets)) ?? [:]
        excludedItems = Set((try? c.decodeIfPresent([String].self, forKey: .excludedItems)) ?? [])
        dismissedSuggestions = Set((try? c.decodeIfPresent([String].self, forKey: .dismissedSuggestions)) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(groups, forKey: .groups)
        try c.encode(targets, forKey: .targets)
        try c.encode(excludedItems.sorted(), forKey: .excludedItems)
        try c.encode(dismissedSuggestions.sorted(), forKey: .dismissedSuggestions)
    }
}
