import Foundation

struct Course: Identifiable, Hashable, Sendable {
    let number: Int
    let name: String
    let folderName: String

    var id: String { folderName }

    /// Parses a folder name such as "08 - Teoria de Control II". Returns nil if it does not match.
    init?(folderName: String) {
        let parts = folderName.components(separatedBy: " - ")
        guard parts.count >= 2, let n = Int(parts[0]) else { return nil }
        self.number = n
        self.name = parts.dropFirst().joined(separator: " - ")
        self.folderName = folderName
    }
}
