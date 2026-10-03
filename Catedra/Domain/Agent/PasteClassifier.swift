import Foundation

/// What a paste in the composer should do, decided from the pasteboard's contents.
enum PasteContent: Equatable {
    /// Files copied in Finder: insert their paths and attach them.
    case files([URL])
    /// Image data only (e.g. a screenshot): save it and attach the saved file.
    case image
    /// Anything else: the normal text paste.
    case text
}

enum PasteClassifier {
    /// Files win (Finder also puts an icon and the name on the pasteboard); an image counts only when there is no text
    /// (rich text copied from documents often carries a rendering of itself).
    static func classify(fileURLs: [URL], hasImage: Bool, hasText: Bool) -> PasteContent {
        if !fileURLs.isEmpty { return .files(fileURLs) }
        if hasImage, !hasText { return .image }
        return .text
    }
}
