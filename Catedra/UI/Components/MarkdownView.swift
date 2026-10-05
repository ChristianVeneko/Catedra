import SwiftUI

/// Renders a Markdown string block by block (inline styling via AttributedString).
struct MarkdownView: View {
    let source: String
    var skipFirstHeading = false
    /// Folder of the Markdown file; relative image paths resolve against it.
    var baseURL: URL?

    var body: some View {
        let blocks = MarkdownParser.parse(source)
        let visible = skipFirstHeading && blocks.first.map({ if case .heading(1, _) = $0 { true } else { false } }) == true
            ? Array(blocks.dropFirst()) : blocks
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, block in
                BlockView(block: block, baseURL: baseURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct BlockView: View {
    let block: MarkdownBlock
    let baseURL: URL?

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(headingFont(level)).padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            inline(text).fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker(for: item).foregroundStyle(.secondary).monospacedDigit()
                        inline(item.text).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 20)
                }
            }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code).font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .table(let header, let alignments, let rows):
            tableView(header: header, alignments: alignments, rows: rows)
        case .image(let alt, let url):
            MarkdownImageView(alt: alt, source: MarkdownImageSource.resolve(url, relativeTo: baseURL), reference: url)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 3)
                inline(text).foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
        } else if item.ordered {
            Text("\(item.number ?? 1).")
        } else {
            Text(["•", "◦", "▪"][item.depth % 3])
        }
    }

    private func tableView(header: [String], alignments: [MarkdownTableAlignment], rows: [[String]]) -> some View {
        let grid = Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { c, text in
                    tableCell(text, alignment: alignments[c], background: Color.secondary.opacity(0.14)).fontWeight(.semibold)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, text in
                        tableCell(text, alignment: alignments[c], background: r.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06))
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        return ViewThatFits(in: .horizontal) {
            grid
            ScrollView(.horizontal) { grid.padding(1) }
        }
    }

    private func tableCell(_ text: String, alignment: MarkdownTableAlignment, background: Color) -> some View {
        let multiline: TextAlignment = alignment == .center ? .center : (alignment == .right ? .trailing : .leading)
        let frame: Alignment = alignment == .center ? .center : (alignment == .right ? .trailing : .leading)
        return inline(text)
            .multilineTextAlignment(multiline)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: frame)
            .background(background)
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
