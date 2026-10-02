import Foundation

enum CollisionNamer {
    /// "a.pdf" -> "a (2).pdf" -> "a (3).pdf" until `isTaken` is false.
    static func uniqueName(for name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            if !isTaken(candidate) { return candidate }
            n += 1
        }
    }
}

/// Copies (never moves) files into `entrega/`, `preparacion/` or `apuntes/` of an activity.
struct FileSystemImporter: FileImporting {
    let workspaceRoot: URL

    func importFiles(_ sources: [URL], into target: ImportTarget, activityFolder: URL) throws -> [URL] {
        let fm = FileManager.default
        let rootPath = Self.canonical(workspaceRoot)
        let activity = Self.canonical(activityFolder)

        guard activity.hasPrefix(rootPath + "/") else { throw ImportError.outsideWorkspace }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: activity, isDirectory: &isDir), isDir.boolValue else { throw ImportError.notADirectory }

        let targetURL = URL(fileURLWithPath: activity).appendingPathComponent(target.folderName, isDirectory: true)
        // If the target exists (possibly as a symlink), its real location must stay inside the activity folder.
        if fm.fileExists(atPath: targetURL.path) {
            let real = Self.canonical(targetURL)
            guard real == activity + "/" + target.folderName else { throw ImportError.outsideWorkspace }
        } else {
            try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
        }

        var results: [URL] = []
        for source in sources {
            let name = CollisionNamer.uniqueName(for: source.lastPathComponent) {
                fm.fileExists(atPath: targetURL.appendingPathComponent($0).path)
            }
            let destination = targetURL.appendingPathComponent(name)
            do { try fm.copyItem(at: source, to: destination) }
            catch { throw ImportError.copyFailed(source.lastPathComponent) }
            results.append(destination)
        }
        return results
    }

    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
