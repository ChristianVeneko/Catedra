import Foundation

/// Stores one Codable document as JSON in `~/Library/Application Support/Catedra/<name>`.
struct JSONStateStore<Value: Codable & Sendable>: StateStoring {
    let file: URL

    init(file: URL) { self.file = file }

    init(name: String) { self.init(file: Self.supportFile(name)) }

    static func supportFile(_ name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Catedra/\(name)")
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: file, options: .atomic)
    }
}

/// Never touches disk; used under tests.
final class MemoryStateStore<Value: Codable & Sendable>: StateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    init(_ value: Value? = nil) { self.value = value }

    func load() -> Value? { lock.withLock { value } }
    func save(_ value: Value) throws { lock.withLock { self.value = value } }
}
