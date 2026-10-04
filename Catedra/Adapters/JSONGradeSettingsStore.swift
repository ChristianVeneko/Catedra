import Foundation

/// Stores `GradeSettings` in `~/Library/Application Support/Catedra/grade-settings.json`.
struct JSONGradeSettingsStore: GradeSettingsStoring {
    let file: URL

    init(file: URL = JSONGradeSettingsStore.defaultFile) { self.file = file }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catedra/grade-settings.json")
    }

    func load() -> GradeSettings {
        guard let data = try? Data(contentsOf: file), let settings = try? JSONDecoder().decode(GradeSettings.self, from: data) else {
            return GradeSettings()
        }
        return settings
    }

    func save(_ settings: GradeSettings) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: file, options: .atomic)
    }
}
