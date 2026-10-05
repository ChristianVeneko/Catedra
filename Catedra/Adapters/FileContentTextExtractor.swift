import Foundation
import PDFKit

/// Text from PDFs (`PDFDocument.string`, per page) and from UTF-8 text files. Unreadable files yield no pages.
struct FileContentTextExtractor: ContentTextExtracting {
    func pages(at url: URL, kind: IndexedFileKind) -> [IndexedPage] {
        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: url), !document.isLocked else { return [] }
            return (0..<document.pageCount).compactMap { index in
                guard let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
                else { return nil }
                return IndexedPage(page: index + 1, text: text)
            }
        case .text:
            guard let text = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return [] }
            return [IndexedPage(page: 0, text: text)]
        }
    }
}
