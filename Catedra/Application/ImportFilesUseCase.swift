import Foundation

struct ImportFilesUseCase: Sendable {
    let makeImporter: @Sendable (URL) -> FileImporting

    func execute(sources: [URL], target: ImportTarget, activity: Activity, root: URL) throws -> [URL] {
        let folder = root.appendingPathComponent(activity.folder, isDirectory: true)
        return try makeImporter(root).importFiles(sources, into: target, activityFolder: folder)
    }
}
