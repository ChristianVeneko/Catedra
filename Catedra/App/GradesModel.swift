import Foundation
import Observation

/// State of the "Notas" destination: the user's grade settings (grouping, targets, exclusions) and the selected subject.
@Observable @MainActor
final class GradesModel {
    private(set) var settings = GradeSettings()
    var selectedSubjectID: String?
    var isGroupingPresented = false
    private let store: GradeSettingsStoring

    init(store: GradeSettingsStoring = JSONGradeSettingsStore()) {
        self.store = store
    }

    func load() { settings = store.load() }

    func subjects(in snapshot: WorkspaceSnapshot) -> [SubjectGrades] {
        GradeDashboard.build(reports: snapshot.gradeReports, activities: snapshot.activities, events: snapshot.calendarEvents,
                             courses: snapshot.courses, settings: settings)
    }

    func courseRefs(in snapshot: WorkspaceSnapshot) -> [GradeCourseRef] {
        GradeDashboard.courseRefs(reports: snapshot.gradeReports, activities: snapshot.activities, events: snapshot.calendarEvents,
                                  courses: snapshot.courses)
    }

    func suggestions(in snapshot: WorkspaceSnapshot) -> [SubjectSuggestion] {
        SubjectGrouping.suggestions(courses: courseRefs(in: snapshot), groups: settings.groups, dismissed: settings.dismissedSuggestions)
    }

    func setTarget(_ percent: Double, forSubject id: String) { update { $0.setTarget(percent, forSubject: id) } }
    func toggleExcluded(_ lineID: String) { update { $0.toggleExcluded(lineID) } }
    func group(_ keys: [String]) { update { $0.group(keys) } }
    func ungroup(_ key: String) { update { $0.ungroup(key) } }
    func dismiss(_ suggestion: SubjectSuggestion) { update { $0.dismissSuggestion(suggestion.courseKeys) } }

    private func update(_ change: (inout GradeSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        try? store.save(next)
    }
}
