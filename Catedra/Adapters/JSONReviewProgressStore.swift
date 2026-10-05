import Foundation

/// Stores review progress in `~/Library/Application Support/Catedra/review-progress.json`.
struct JSONReviewProgressStore: ReviewProgressStoring {
    let file: URL

    init(file: URL = JSONReviewProgressStore.defaultFile) { self.file = file }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catedra/review-progress.json")
    }

    func load() -> ReviewProgressFile {
        guard let data = try? Data(contentsOf: file) else { return ReviewProgressFile() }
        if let decoded = try? JSONDecoder().decode(ReviewProgressFile.self, from: data) { return decoded }
        // Unreadable file: keep a copy so the next save cannot silently destroy the user's progress.
        let backup = file.deletingLastPathComponent().appendingPathComponent("review-progress.corrupt.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: file, to: backup)
        return ReviewProgressFile()
    }

    func save(_ progress: ReviewProgressFile) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(progress).write(to: file, options: .atomic)
    }
}
