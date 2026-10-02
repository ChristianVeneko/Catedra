import Foundation

/// Where a Markdown image lives, resolved against the folder of the Markdown file.
enum MarkdownImageSource: Equatable {
    case local(URL)
    case remote(URL)
    case unresolved

    static func resolve(_ reference: String, relativeTo base: URL?) -> MarkdownImageSource {
        let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty, !ref.lowercased().hasPrefix("data:") else { return .unresolved }
        let lower = ref.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: ref).map(MarkdownImageSource.remote) ?? .unresolved
        }
        if lower.hasPrefix("file://"), let url = URL(string: ref), url.isFileURL { return .local(url) }
        let path = ref.removingPercentEncoding ?? ref
        if path.hasPrefix("/") { return .local(URL(fileURLWithPath: path)) }
        guard let base else { return .unresolved }
        return .local(base.appendingPathComponent(path).standardizedFileURL)
    }
}
