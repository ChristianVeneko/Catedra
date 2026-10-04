import Foundation

/// Finds the course folder a Moodle grade report belongs to (reports only carry the Moodle course id).
enum GradeCourseResolver {
    static func folder(for report: GradeReport, activities: [Activity], events: [CalendarEvent], courses: [Course]) -> String? {
        let known = Set(courses.map(\.folderName))
        var votes: [String: Int] = [:]
        let cmids = Set(report.items.compactMap(\.cmid))
        for activity in activities {
            if let cmid = activity.cmid, cmids.contains(cmid), known.contains(activity.courseFolderName) {
                votes[activity.courseFolderName, default: 0] += 1
            }
        }
        if let best = votes.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) { return best.key }
        guard let name = events.first(where: { $0.courseId == report.courseId && !$0.courseName.isEmpty })?.courseName else { return nil }
        let folded = GradeRules.fold(name)
        if let exact = courses.first(where: { GradeRules.fold($0.name) == folded }) { return exact.folderName }
        return courses.first { GradeRules.fold($0.name).contains(folded) || folded.contains(GradeRules.fold($0.name)) }?.folderName
    }
}

struct SubjectGrades: Identifiable, Equatable, Sendable {
    let subject: GradeSubject
    let lines: [GradeLine]
    let summary: GradeSummary
    var id: String { subject.id }
}

enum GradeDashboard {
    /// Course refs the grades feature works with: every course folder plus reports that matched no folder ("Curso <id>").
    static func courseRefs(reports: [GradeReport], activities: [Activity], events: [CalendarEvent], courses: [Course]) -> [GradeCourseRef] {
        var refs = courses.map { GradeCourseRef(key: $0.folderName, name: $0.name) }
        for report in reports where GradeCourseResolver.folder(for: report, activities: activities, events: events, courses: courses) == nil {
            refs.append(GradeCourseRef(key: "course-\(report.courseId)", name: "Curso \(report.courseId)"))
        }
        return refs
    }

    static func build(reports: [GradeReport], activities: [Activity], events: [CalendarEvent], courses: [Course],
                      settings: GradeSettings) -> [SubjectGrades] {
        var linesByCourse: [String: [GradeLine]] = [:]
        for report in reports {
            let key = GradeCourseResolver.folder(for: report, activities: activities, events: events, courses: courses)
                ?? "course-\(report.courseId)"
            linesByCourse[key, default: []] += GradeRules.lines(report: report, courseKey: key, excluded: settings.excludedItems)
        }
        let refs = courseRefs(reports: reports, activities: activities, events: events, courses: courses)
        return SubjectGrouping.subjects(courses: refs, groups: settings.groups).compactMap { subject in
            let lines = subject.courseKeys.flatMap { linesByCourse[$0] ?? [] }
            guard !lines.isEmpty else { return nil }
            return SubjectGrades(subject: subject, lines: lines,
                                 summary: GradeCalculator.summary(lines: lines, targetPercent: settings.target(forSubject: subject.id)))
        }
    }
}
