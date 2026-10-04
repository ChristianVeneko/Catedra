import Foundation

/// One gradeable item of a course, ready for point arithmetic. Pure value.
struct GradeLine: Identifiable, Hashable, Sendable {
    /// Stable key: `<courseKey>#cmid<cmid>` or `<courseKey>#<folded name>`.
    let id: String
    /// Course folder name (or `course-<id>` when the report could not be matched to a folder).
    let courseKey: String
    let name: String
    let module: String
    let cmid: Int?
    let earned: Double?
    /// Maximum points of the item; 0 when unknown.
    let max: Double
    let gradedAt: Date?
    let feedback: String
    /// "Diferido" / "Sustitutivo" items replace another exam.
    let isMakeup: Bool
    /// Extra-credit items add earned points but never possible points.
    let isExtra: Bool
    /// The user marked the item "no cuenta".
    var excluded: Bool

    var isGraded: Bool { earned != nil }

    /// Part of the points the subject can still be worth: not excluded, not extra credit, and a makeup only once graded.
    var countsTowardPossible: Bool { !excluded && !isExtra && max > 0 && (!isMakeup || isGraded) }

    /// Graded and not excluded; extra credit and grades above the maximum count in full.
    var countsTowardEarned: Bool { !excluded && isGraded }
}

enum GradeRules {
    /// Moodle rows that carry points of their own; category and course rows are aggregates and never summed.
    static func isGradeable(_ item: GradeItem) -> Bool { item.itemType == "mod" || item.itemType == "manual" }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ name: String) -> [String] {
        fold(name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func isMakeup(_ name: String) -> Bool {
        !Set(words(name)).isDisjoint(with: ["diferido", "diferida", "sustitutivo", "sustitutiva", "sustitutorio"])
    }

    static func isExtra(_ name: String) -> Bool {
        !Set(words(name)).isDisjoint(with: ["extra", "bonus"])
    }

    static func itemKey(courseKey: String, item: GradeItem) -> String {
        if let cmid = item.cmid { return "\(courseKey)#cmid\(cmid)" }
        return "\(courseKey)#\(fold(item.name))"
    }

    static func lines(report: GradeReport, courseKey: String, excluded: Set<String>) -> [GradeLine] {
        report.items.filter(isGradeable).map { item in
            let id = itemKey(courseKey: courseKey, item: item)
            return GradeLine(id: id, courseKey: courseKey, name: item.name, module: item.itemModule, cmid: item.cmid,
                             earned: item.gradeRaw, max: Swift.max(0, item.gradeMax ?? 0), gradedAt: item.gradedAt,
                             feedback: item.feedback, isMakeup: isMakeup(item.name), isExtra: isExtra(item.name),
                             excluded: excluded.contains(id))
        }
    }
}
