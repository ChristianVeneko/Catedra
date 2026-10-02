import Foundation

/// A Moodle activity mirrored on disk. `id` is the workspace-relative folder (unique per activity).
struct Activity: Identifiable, Hashable, Sendable {
    let courseName: String
    let kind: ActivityKind
    let name: String
    let due: Date?
    let rawStatus: String
    let grade: String
    let url: URL?
    let folder: String

    var id: String { folder }

    /// Folder name of the owning course (first path component of `folder`).
    var courseFolderName: String {
        folder.split(separator: "/").first.map(String.init) ?? ""
    }

    var hasGrade: Bool { !grade.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Derived, UI-facing state of an activity.
enum ActivityState: Hashable, Sendable {
    case pending, inProgress, upcoming, submitted, overdue

    static func derive(from activity: Activity, hasUserWork: Bool, now: Date) -> ActivityState {
        let status = activity.rawStatus.lowercased()
        let submittedKeywords = ["entregad", "enviad", "calificad", "submitted", "graded", "finalizad", "completad"]
        if activity.hasGrade || submittedKeywords.contains(where: status.contains) { return .submitted }
        if let due = activity.due, due < now { return .overdue }
        if status.contains("proximo") || status.contains("próximo") { return .upcoming }
        return hasUserWork ? .inProgress : .pending
    }

    var label: String {
        switch self {
        case .pending: "Pendiente"
        case .inProgress: "En progreso"
        case .upcoming: "Próxima"
        case .submitted: "Entregada"
        case .overdue: "Vencida"
        }
    }
}
