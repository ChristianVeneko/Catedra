import AppKit

/// Saves images pasted into the composer as PNG under `~/Library/Application Support/Catedra/attachments/`
/// (never in the workspace) so the agent can read them as files.
struct PastedImageStore {
    let directory: URL

    init(directory: URL = PastedImageStore.defaultDirectory) { self.directory = directory }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catedra/attachments", isDirectory: true)
    }

    /// PNG bytes of the image on `pasteboard`, or nil when it holds none.
    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes the PNG and returns its file URL.
    func save(png: Data, at date: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.prefix(4).lowercased()
        let url = directory.appendingPathComponent("pegado-\(formatter.string(from: date))-\(suffix).png")
        try png.write(to: url, options: .atomic)
        return url
    }
}
