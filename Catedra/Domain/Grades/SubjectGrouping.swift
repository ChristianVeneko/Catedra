import Foundation

/// A course as the grades feature sees it: the folder name (or `course-<id>`) and its display name.
struct GradeCourseRef: Hashable, Sendable {
    let key: String
    let name: String
}

/// One subject: a single course or several classrooms the user merged (e.g. theory + laboratory).
struct GradeSubject: Identifiable, Hashable, Sendable {
    let name: String
    let courseKeys: [String]
    var id: String { courseKeys.joined(separator: "|") }
}

struct SubjectSuggestion: Equatable, Sendable {
    /// `[main course, laboratory course]`.
    let courseKeys: [String]
}

enum SubjectGrouping {
    /// Subjects in course order. Stale group members are ignored, a course belongs to its first group only, and a group that
    /// keeps fewer than two live courses does not merge anything.
    static func subjects(courses: [GradeCourseRef], groups: [[String]]) -> [GradeSubject] {
        let order = Dictionary(courses.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(courses.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var claimed = Set<String>()
        var merged: [[GradeCourseRef]] = []
        for group in groups {
            let members = group.filter { byKey[$0] != nil && !claimed.contains($0) }
            guard Set(members).count >= 2 else { continue }
            claimed.formUnion(members)
            merged.append(members.compactMap { byKey[$0] }.sorted { order[$0.key]! < order[$1.key]! })
        }
        var result: [(Int, GradeSubject)] = merged.map { members in
            let main = members.first { !isLaboratory($0.name) } ?? members[0]
            return (order[members[0].key] ?? 0, GradeSubject(name: main.name, courseKeys: members.map(\.key)))
        }
        for course in courses where !claimed.contains(course.key) {
            result.append((order[course.key] ?? 0, GradeSubject(name: course.name, courseKeys: [course.key])))
        }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func suggestionKey(_ keys: [String]) -> String { keys.sorted().joined(separator: "|") }

    /// Pairs "Laboratorio de X" with a course named "X" (accent and case insensitive), skipping pairs already grouped or dismissed.
    static func suggestions(courses: [GradeCourseRef], groups: [[String]], dismissed: Set<String>) -> [SubjectSuggestion] {
        var result: [SubjectSuggestion] = []
        for lab in courses {
            guard let base = baseName(ofLaboratory: lab.name),
                  let main = courses.first(where: { $0.key != lab.key && GradeRules.fold($0.name) == base }) else { continue }
            let keys = [main.key, lab.key]
            if groups.contains(where: { Set(keys).isSubset(of: Set($0)) }) { continue }
            if dismissed.contains(suggestionKey(keys)) { continue }
            result.append(SubjectSuggestion(courseKeys: keys))
        }
        return result
    }

    static func isLaboratory(_ name: String) -> Bool { baseName(ofLaboratory: name) != nil }

    private static func baseName(ofLaboratory name: String) -> String? {
        let folded = GradeRules.fold(name)
        for prefix in ["laboratorio de ", "laboratorio del ", "laboratorio "] where folded.hasPrefix(prefix) {
            let rest = String(folded.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }
}
