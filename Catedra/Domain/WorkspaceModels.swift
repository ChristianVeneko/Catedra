import Foundation

/// Files of one activity grouped by folder (hidden files excluded).
struct ActivityFiles: Sendable, Equatable {
    var material: [URL] = []
    var entrega: [URL] = []
    var preparacion: [URL] = []
    var apuntes: [URL] = []
    /// `rubrica.md` exists in the activity folder (rubric or marking guide).
    var hasRubric = false

    var hasUserWork: Bool { !entrega.isEmpty || !preparacion.isEmpty }

    func files(in target: ImportTarget) -> [URL] {
        switch target {
        case .entrega: entrega
        case .preparacion: preparacion
        case .apuntes: apuntes
        }
    }
}

/// Node of the `contenidos/` tree or the forum list.
struct ContentNode: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [ContentNode]?

    var id: URL { url }
}

/// Everything the UI needs from a workspace read.
struct WorkspaceSnapshot: Sendable {
    var courses: [Course]
    var activities: [Activity]
    var activitiesWithUserWork: Set<Activity.ID>
    var lastSync: Date?
    /// Phase 4 data; empty when the sync did not produce the files.
    var gradeReports: [GradeReport] = []
    var calendarEvents: [CalendarEvent] = []
    var activitiesWithRubric: Set<Activity.ID> = []

    static let empty = WorkspaceSnapshot(courses: [], activities: [], activitiesWithUserWork: [], lastSync: nil)
}
