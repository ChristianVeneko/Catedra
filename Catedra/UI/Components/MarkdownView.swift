import SwiftUI

/// Renders a Markdown string block by block (inline styling via AttributedString).
struct MarkdownView: View {
    let source: String
    var skipFirstHeading = false

    var body: some View {
        let blocks = MarkdownParser.parse(source)
        let visible = skipFirstHeading && blocks.first.map({ if case .heading(1, _) = $0 { true } else { false } }) == true
            ? Array(blocks.dropFirst()) : blocks
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(headingFont(level)).padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            inline(text).fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(i + 1)." : "•").foregroundStyle(.secondary).monospacedDigit()
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code).font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .table(let rows):
            ScrollView(.horizontal) {
                Text(rows.map { $0.joined(separator: "  |  ") }.joined(separator: "\n"))
                    .font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .image(let alt, let url):
            if let link = URL(string: url) {
                Link(destination: link) { Label(alt.isEmpty ? "Imagen adjunta" : alt, systemImage: "photo") }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 3)
                inline(text).foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) { return Text(attributed) }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.weight(.bold)
        case 2: .title2.weight(.semibold)
        case 3: .title3.weight(.semibold)
        default: .headline
        }
    }
}
