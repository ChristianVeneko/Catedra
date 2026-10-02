import Foundation

/// A one-click agent task with an editable Spanish prompt template.
/// Placeholders: `{{activityName}}`, `{{courseName}}`, `{{kind}}`, `{{due}}`, `{{activitiesList}}`.
struct Recipe: Identifiable, Hashable, Sendable {
    enum Applicability: Hashable, Sendable {
        case activity(Set<ActivityKind>)
        case course
    }

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let applicability: Applicability
    let template: String

    func applies(to scope: AgentScope) -> Bool {
        switch (applicability, scope) {
        case (.activity(let kinds), .activity(let activity)): kinds.contains(activity.kind)
        case (.course, .course): true
        default: false
        }
    }
}
