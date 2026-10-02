import SwiftUI
import AppKit

/// Image block of a Markdown document: local files load asynchronously through `NSImage`, remote ones through
/// `AsyncImage`; anything unavailable becomes a small placeholder with the alt text and a link.
struct MarkdownImageView: View {
    let alt: String
    let source: MarkdownImageSource
    let reference: String

    @State private var preview: URL?

    var body: some View {
        switch source {
        case .local(let url): LocalImage(url: url, alt: alt, preview: $preview)
        case .remote(let url): RemoteImage(url: url, alt: alt)
        case .unresolved: MarkdownImagePlaceholder(alt: alt, caption: reference, link: nil)
        }
    }
}

private let imageCorner = RoundedRectangle(cornerRadius: 10, style: .continuous)

private struct LocalImage: View {
    let url: URL
    let alt: String
    @Binding var preview: URL?
    @State private var phase: Phase = .loading

    private enum Phase { case loading, loaded(NSImage), missing }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width > 0 ? image.size.width : nil, alignment: .leading)
                    .clipShape(imageCorner)
                    .overlay(imageCorner.strokeBorder(.quaternary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { preview = url }
                    .help("Clic para ver con Vista rápida")
                    .accessibilityLabel(alt.isEmpty ? "Imagen" : alt)
            case .missing:
                MarkdownImagePlaceholder(alt: alt, caption: url.lastPathComponent, link: nil)
            }
        }
        .quickLookPreview($preview)
        .task(id: url) {
            phase = .loading
            let loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
            phase = loaded.map(Phase.loaded) ?? .missing
        }
    }
}

private struct RemoteImage: View {
    let url: URL
    let alt: String

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 720, alignment: .leading)
                    .clipShape(imageCorner)
                    .overlay(imageCorner.strokeBorder(.quaternary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .help("Abrir en el navegador")
                    .accessibilityLabel(alt.isEmpty ? "Imagen" : alt)
            case .failure:
                MarkdownImagePlaceholder(alt: alt, caption: url.host() ?? url.absoluteString, link: url)
            default:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
    }
}

struct MarkdownImagePlaceholder: View {
    let alt: String
    let caption: String
    let link: URL?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(alt.isEmpty ? "Imagen no disponible" : alt).font(.callout)
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if let link {
                Spacer(minLength: 8)
                Link("Abrir", destination: link).font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: imageCorner)
    }
}
