import Foundation

/// Stores the study blocks as one JSON array in `~/Library/Application Support/Catedra/study-blocks.json`.
struct JSONStudyBlockStore: StudyBlockStoring {
    let file: URL

    init(file: URL = JSONStudyBlockStore.defaultFile) { self.file = file }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catedra/study-blocks.json")
    }

    func load() -> [StudyBlock] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([Lossy<StudyBlock>].self, from: data) else { return [] }
        return items.compactMap(\.value)
    }

    func save(_ blocks: [StudyBlock]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(blocks).write(to: file, options: .atomic)
    }

    /// Decodes one element, yielding nil instead of failing the whole array.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}
