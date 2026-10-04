import Foundation

/// A grade or teacher feedback that appeared or changed between two syncs.
struct GradeChange: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case newGrade, gradeChanged, feedback }
    let kind: Kind
    let itemName: String
    let courseName: String
    /// Formatted grade, empty for feedback-only changes.
    let grade: String
    var cmid: Int? = nil
}

enum GradeChangeDetector {
    /// Changes from `before` to `after`. Nothing is reported for courses that had no data before (first sync).
    static func changes(before: WorkspaceSnapshot, after: WorkspaceSnapshot) -> [GradeChange] {
        var result = reportChanges(before: before, after: after)
        let covered = Set(result.compactMap(\.cmid))
        result += activityChanges(before: before.activities, after: after.activities).filter { change in
            change.cmid.map { !covered.contains($0) } ?? true
        }
        return result
    }

    private static func reportChanges(before: WorkspaceSnapshot, after: WorkspaceSnapshot) -> [GradeChange] {
        let oldReports = Dictionary(before.gradeReports.map { ($0.courseId, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [GradeChange] = []
        for report in after.gradeReports {
            guard let old = oldReports[report.courseId] else { continue }
            let courseName = courseName(of: report, in: after)
            func key(_ item: GradeItem) -> String { item.cmid.map { "cmid\($0)" } ?? "name:" + GradeRules.fold(item.name) }
            let oldItems = Dictionary(old.items.filter(GradeRules.isGradeable).map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
            for item in report.items where GradeRules.isGradeable(item) {
                let previous = oldItems[key(item)]
                func change(_ kind: GradeChange.Kind) -> GradeChange {
                    GradeChange(kind: kind, itemName: item.name, courseName: courseName,
                                grade: kind == .feedback ? "" : formatted(item), cmid: item.cmid)
                }
                if let now = item.gradeRaw {
                    if previous?.gradeRaw == nil { result.append(change(.newGrade)); continue }
                    if previous?.gradeRaw != now { result.append(change(.gradeChanged)); continue }
                }
                if hasText(item.feedback), item.feedback != previous?.feedback { result.append(change(.feedback)) }
            }
        }
        return result
    }

    private static func activityChanges(before: [Activity], after: [Activity]) -> [GradeChange] {
        let old = Dictionary(before.map { ($0.folder, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [GradeChange] = []
        for activity in after {
            guard let previous = old[activity.folder] else { continue }
            func change(_ kind: GradeChange.Kind) -> GradeChange {
                GradeChange(kind: kind, itemName: activity.name, courseName: activity.courseName,
                            grade: kind == .feedback ? "" : activity.grade, cmid: activity.cmid)
            }
            if activity.hasGrade, activity.grade != previous.grade {
                result.append(change(previous.hasGrade ? .gradeChanged : .newGrade))
            } else if activity.hasFeedback, activity.feedback != previous.feedback {
                result.append(change(.feedback))
            }
        }
        return result
    }

    private static func formatted(_ item: GradeItem) -> String {
        let text = item.gradeFormatted.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty, text != "-" { return text }
        return item.gradeRaw.map(GradeFormat.points) ?? ""
    }

    private static func hasText(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private static func courseName(of report: GradeReport, in snapshot: WorkspaceSnapshot) -> String {
        if let folder = GradeCourseResolver.folder(for: report, activities: snapshot.activities, events: snapshot.calendarEvents,
                                                   courses: snapshot.courses),
           let course = snapshot.courses.first(where: { $0.folderName == folder }) { return course.name }
        return "Curso \(report.courseId)"
    }
}

/// Wording and policy of the "new grade" system notification.
enum GradeChangeNotification {
    static func content(for changes: [GradeChange]) -> (title: String, body: String)? {
        guard let first = changes.first else { return nil }
        guard changes.count == 1 else {
            return ("Cátedra: novedades en sus notas", "\(changes.count) novedades: " + changes.prefix(3).map(\.itemName).joined(separator: ", ")
                    + (changes.count > 3 ? "…" : ""))
        }
        switch first.kind {
        case .newGrade: return ("Cátedra: nueva nota", "\(first.courseName) · \(first.itemName): \(first.grade)")
        case .gradeChanged: return ("Cátedra: nota actualizada", "\(first.courseName) · \(first.itemName): \(first.grade)")
        case .feedback: return ("Cátedra: nueva retroalimentación", "\(first.courseName) · \(first.itemName)")
        }
    }

    /// An explicit choice wins; with none, notifications are on only when the system permission is already granted.
    static func isEnabled(preference: Bool?, permission: NotificationPermission) -> Bool {
        preference ?? (permission == .authorized)
    }
}

enum GradeFormat {
    /// "66,7 %".
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Formatters.locale)) + " %"
    }

    /// "17,5" / "20" in the app's Spanish locale.
    static func points(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded.formatted(.number.precision(.fractionLength(0...2)).locale(Formatters.locale))
    }
}

/// Spanish sentence of the "¿Cuánto necesito?" simulator.
enum GradeNeedText {
    static func describe(summary: GradeSummary, targetPercent: Double) -> String {
        guard summary.hasData else { return "Aún no hay evaluaciones con puntos." }
        let need = summary.needed(forTargetPercent: targetPercent)
        let target = GradeFormat.points(targetPercent / 100 * summary.totalPossible)
        if need.isMet { return "Ya alcanzó la meta de \(target) pts." }
        if !need.isReachable {
            if summary.remaining == 0 {
                return "No quedan evaluaciones pendientes y los \(GradeFormat.points(summary.earned)) pts no alcanzan la meta de \(target) pts."
            }
            return "La meta de \(target) pts ya no es alcanzable: con el máximo en lo pendiente llegaría a "
                + "\(GradeFormat.points(summary.earned + summary.remaining)) pts."
        }
        let average = (need.averageFraction ?? 0) * 100
        return "Necesita \(GradeFormat.points(need.points)) pts de los \(GradeFormat.points(summary.remaining)) que quedan: "
            + "un promedio de \(GradeFormat.percent(average)) en lo pendiente."
    }
}
