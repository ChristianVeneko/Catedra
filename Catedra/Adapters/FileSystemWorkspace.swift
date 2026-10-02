import Foundation

/// Reads the Moodle mirror from disk: `activities.json` plus the course folder tree.
struct FileSystemWorkspace: WorkspaceReading {
    static let activitiesRelativePath = "_sistema/data/activities.json"

    func loadSnapshot(root: URL) throws -> WorkspaceSnapshot {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let courses = entries
            .filter { isDirectory($0) }
            .compactMap { Course(folderName: $0.lastPathComponent) }
            .sorted { $0.number < $1.number }

        let jsonURL = root.appendingPathComponent(Self.activitiesRelativePath)
        var activities: [Activity] = []
        var lastSync: Date?
        if fm.fileExists(atPath: jsonURL.path) {
            activities = try ActivityJSONDecoder.decode(Data(contentsOf: jsonURL))
            lastSync = (try? fm.attributesOfItem(atPath: jsonURL.path)[.modificationDate]) as? Date
        }

        var withWork = Set<Activity.ID>()
        for activity in activities where files(root: root, activity: activity).hasUserWork {
            withWork.insert(activity.id)
        }
        return WorkspaceSnapshot(courses: courses, activities: activities, activitiesWithUserWork: withWork, lastSync: lastSync)
    }

    func files(root: URL, activity: Activity) -> ActivityFiles {
        let base = root.appendingPathComponent(activity.folder, isDirectory: true)
        func list(_ name: String) -> [URL] { visibleChildren(of: base.appendingPathComponent(name, isDirectory: true)) }
        return ActivityFiles(material: list("material"), entrega: list("entrega"),
                             preparacion: list("preparacion"), apuntes: list("apuntes"))
    }

    func contentTree(root: URL, course: Course) -> [ContentNode] {
        tree(at: root.appendingPathComponent(course.folderName).appendingPathComponent("contenidos", isDirectory: true))
    }

    func forums(root: URL, course: Course) -> [ContentNode] {
        tree(at: root.appendingPathComponent(course.folderName).appendingPathComponent("foros", isDirectory: true))
    }

    // MARK: - Helpers

    private func tree(at url: URL) -> [ContentNode] {
        visibleChildren(of: url).map { child in
            let dir = isDirectory(child)
            return ContentNode(url: child, name: child.lastPathComponent, isDirectory: dir,
                               children: dir ? tree(at: child) : nil)
        }
    }

    private func visibleChildren(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
