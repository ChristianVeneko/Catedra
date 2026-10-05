import Foundation
import Observation

@Observable @MainActor
final class ActivityDetailModel {
    let activity: Activity
    private(set) var files = ActivityFiles()
    private(set) var statement: String?
    private(set) var review: DraftReviewLoadState = .missing
    var importTarget: ImportTarget
    var message: String?
    var isError = false

    private let root: URL
    private let reader: WorkspaceReading
    private let importer: ImportFilesUseCase
    private let onChange: @MainActor () async -> Void

    init(activity: Activity, root: URL, reader: WorkspaceReading, importer: ImportFilesUseCase,
         onChange: @escaping @MainActor () async -> Void) {
        self.activity = activity
        self.root = root
        self.reader = reader
        self.importer = importer
        self.onChange = onChange
        self.importTarget = activity.kind.defaultImportTarget
        reload()
    }

    /// The pre-delivery review needs something in `entrega/` to look at.
    var canReview: Bool { !files.entrega.isEmpty }

    var folderURL: URL { root.appendingPathComponent(activity.folder, isDirectory: true) }

    func reload() {
        files = reader.files(root: root, activity: activity)
        let statementURL = folderURL.appendingPathComponent("enunciado.md")
        statement = try? String(contentsOf: statementURL, encoding: .utf8)
        review = DraftReviewFile.load(in: folderURL)
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        do {
            let copied = try importer.execute(sources: urls, target: importTarget, activity: activity, root: root)
            message = "Se copiaron \(copied.count) archivo(s) a «\(importTarget.label)»."
            isError = false
            reload()
            await onChange()
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}
