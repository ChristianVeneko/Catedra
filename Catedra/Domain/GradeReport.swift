import Foundation

/// One row of a course grade report (`_sistema/data/grades_<courseid>.json`).
struct GradeItem: Hashable, Sendable {
    let name: String
    let itemType: String
    let itemModule: String
    let cmid: Int?
    let gradeRaw: Double?
    let gradeFormatted: String
    let gradeMin: Double?
    let gradeMax: Double?
    let weight: Double?
    let percentage: String
    let feedback: String
    let submittedAt: Date?
    let gradedAt: Date?
}

/// Structured grades of one course: graded items plus the course total row.
struct GradeReport: Hashable, Sendable {
    let courseId: Int
    let items: [GradeItem]
    let total: GradeItem?
}

/// A Moodle calendar event (`_sistema/data/calendar.json`).
struct CalendarEvent: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let courseId: Int?
    let courseName: String
    let eventType: String
    let moduleName: String
    let start: Date
    let duration: TimeInterval
    let url: URL?
    let cmid: Int?
}
