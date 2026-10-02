import Foundation

/// Dotted version number (major.minor.patch) used to compare tool versions.
struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    /// First dotted version in a tool's output ("Python 3.14.0", "git version 2.50.1 (Apple Git-155)", "v22.3").
    static func parse(_ output: String) -> SemanticVersion? {
        guard let range = output.range(of: #"\d+(\.\d+){0,2}"#, options: .regularExpression) else { return nil }
        let parts = output[range].split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return nil }
        return SemanticVersion(major, parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0)
    }

    static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}
