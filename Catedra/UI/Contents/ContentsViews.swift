import SwiftUI
import PDFKit
import QuickLookUI

/// Tree of `contenidos/` (or the list of forums) for one course.
struct ContentTreeView: View {
    @Environment(AppContainer.self) private var container
    let title: String
    let nodes: [ContentNode]
    let emptyText: String

    var body: some View {
        @Bindable var nav = container.navigation
        Group {
            if nodes.isEmpty {
                ContentUnavailableView("Sin contenido", systemImage: "folder", description: Text(emptyText))
            } else {
                List(nodes, children: \.children, selection: $nav.selectedNodeURL) { node in
                    Label(displayName(node), systemImage: icon(node)).lineLimit(1).tag(node.url)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(title)
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
    }

    private func displayName(_ node: ContentNode) -> String {
        node.isDirectory ? node.name : node.url.deletingPathExtension().lastPathComponent
    }

    private func icon(_ node: ContentNode) -> String {
        if node.isDirectory { return "folder" }
        switch node.url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "md", "txt": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif": return "photo"
        default: return "doc"
        }
    }
}

/// Preview of a file selected in the contents browser: Markdown, PDF or Quick Look.
struct FilePreviewView: View {
    let url: URL
    /// 1-based page a PDF opens at (full-text results).
    var initialPage: Int?

    var body: some View {
        Group {
            switch url.pathExtension.lowercased() {
            case "md", "txt":
                ScrollView {
                    MarkdownView(source: (try? String(contentsOf: url, encoding: .utf8)) ?? "No se pudo leer el archivo.",
                                 baseURL: url.deletingLastPathComponent())
                        .padding(24).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
                }
            case "pdf":
                PDFPreview(url: url, page: initialPage)
            default:
                QuickLookPreview(url: url)
            }
        }
        .navigationTitle(url.lastPathComponent)
        .toolbar {
            ToolbarItem {
                Button { NSWorkspace.shared.open(url) } label: { Label("Abrir", systemImage: "arrow.up.forward.app") }
            }
            ToolbarItem {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Mostrar en Finder", systemImage: "folder") }
            }
        }
    }
}

struct PDFPreview: NSViewRepresentable {
    let url: URL
    /// 1-based page to scroll to when the document is first shown.
    var page: Int?
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
        if let page, let document = view.document, let target = document.page(at: min(max(page, 1), document.pageCount) - 1) {
            DispatchQueue.main.async { view.go(to: target) }
        }
    }
}

struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }
}
