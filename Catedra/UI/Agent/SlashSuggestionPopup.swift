import SwiftUI

/// Floating list of slash-command suggestions shown above the composer. Keyboard focus stays in the editor;
/// selection is driven by `ComposerModel`.
struct SlashSuggestionPopup: View {
    let model: ComposerModel
    let accept: (Int) -> Void

    static let rowHeight: CGFloat = 36
    static let maxVisibleRows = 8

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.sections) { section in
                        Text(section.title.uppercased())
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                        ForEach(section.matches) { match in
                            let index = model.flat.firstIndex(of: match) ?? 0
                            SlashSuggestionRow(match: match, selected: index == model.selectedIndex)
                                .id(match.id)
                                .contentShape(Rectangle())
                                .onTapGesture { accept(index) }
                                .onHover { inside in
                                    if inside, model.selectedIndex != index { model.selectedIndex = index }
                                }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
            .frame(height: Self.height(for: model))
            .onChange(of: model.selectedIndex) { _, index in
                guard model.flat.indices.contains(index) else { return }
                proxy.scrollTo(model.flat[index].id)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sugerencias de comandos")
    }

    /// Rows plus section headers, capped at ~8 rows.
    static func height(for model: ComposerModel) -> CGFloat {
        let rows = CGFloat(model.flat.count)
        let headers = CGFloat(model.sections.count) * 26
        return min(rows * Self.rowHeight + headers + 8, CGFloat(Self.maxVisibleRows) * Self.rowHeight + 34)
    }
}

private struct SlashSuggestionRow: View {
    let match: SlashCommandMatch
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: match.command))
                .frame(width: 18).foregroundStyle(selected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(highlightedName)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .lineLimit(1)
                    if let hint = match.command.argumentHint {
                        Text(hint).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.8)).lineLimit(1)
                    }
                }
                if !match.command.description.isEmpty {
                    Text(match.command.description).font(.caption).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: SlashSuggestionPopup.rowHeight, alignment: .leading)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 4)
    }

    private var highlightedName: AttributedString {
        var text = AttributedString("/")
        let marked = Set(match.highlight)
        for (index, character) in match.command.name.enumerated() {
            var piece = AttributedString(String(character))
            if marked.contains(index) {
                piece.foregroundColor = selected ? .white : .accentColor
                piece.underlineStyle = .single
            }
            text += piece
        }
        return text
    }

    static func symbol(for command: SlashCommand) -> String {
        switch command.kind {
        case .builtin: "command"
        case .skill: "wand.and.stars"
        case .app:
            switch command.name {
            case "resume": "clock.arrow.circlepath"
            case "new": "plus.bubble"
            case "model": "cpu"
            case "permisos": "lock.shield"
            case "recetas": "rectangle.stack"
            case "terminal": "terminal"
            case "archivos": "doc.on.doc"
            default: "slash.circle"
            }
        }
    }
}
