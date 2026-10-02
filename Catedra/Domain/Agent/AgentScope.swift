import Foundation

enum AgentScopeKind: String, Codable, Sendable {
    case activity, course
}

/// Persistable reference to a scope (workspace-relative folder), independent of the live workspace snapshot.
struct AgentScopeRef: Codable, Hashable, Sendable {
    let kind: AgentScopeKind
    let folder: String
    let title: String

    var id: String { folder }

    /// Folder name of the owning course (first path component).
    var courseFolderName: String { folder.split(separator: "/").first.map(String.init) ?? folder }

    func url(in root: URL) -> URL { root.appendingPathComponent(folder, isDirectory: true) }
}

/// Where an agent runs: inside one activity folder or inside a whole course folder.
enum AgentScope: Hashable, Sendable {
    case activity(Activity)
    case course(Course)

    var ref: AgentScopeRef {
        switch self {
        case .activity(let a): AgentScopeRef(kind: .activity, folder: a.folder, title: a.name)
        case .course(let c): AgentScopeRef(kind: .course, folder: c.folderName, title: c.name)
        }
    }

    var id: String { ref.id }
    var folder: String { ref.folder }
    var title: String { ref.title }
    var kind: AgentScopeKind { ref.kind }

    func url(in root: URL) -> URL { ref.url(in: root) }
}
