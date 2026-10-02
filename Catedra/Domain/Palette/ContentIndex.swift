import Foundation

/// A file under a course's `contenidos/` folder, searchable from the palette.
struct ContentIndexEntry: Hashable, Sendable {
    let courseFolder: String
    let courseName: String
    let url: URL
    let name: String
    /// Folder of the file relative to `contenidos/` ("" at the top level).
    let parentPath: String
}

/// Flattens the contents trees of all courses. Generated `_imagenes` folders are never indexed.
enum ContentIndexBuilder {
    static func entries(root: URL, courses: [Course], reader: WorkspaceReading) -> [ContentIndexEntry] {
        var result: [ContentIndexEntry] = []
        for course in courses {
            flatten(reader.contentTree(root: root, course: course), course: course, parent: "", into: &result)
        }
        return result
    }

    private static func flatten(_ nodes: [ContentNode], course: Course, parent: String, into result: inout [ContentIndexEntry]) {
        for node in nodes {
            if node.isDirectory {
                guard !FileSystemWorkspace.hiddenFolderNames.contains(node.name) else { continue }
                flatten(node.children ?? [], course: course, parent: parent.isEmpty ? node.name : parent + "/" + node.name, into: &result)
            } else {
                result.append(ContentIndexEntry(courseFolder: course.folderName, courseName: course.name, url: node.url,
                                                name: node.name, parentPath: parent))
            }
        }
    }
}
