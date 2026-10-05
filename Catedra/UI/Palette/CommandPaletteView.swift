import SwiftUI

/// Spotlight-style overlay: search field plus grouped results, fully keyboard driven.
struct CommandPaletteView: View {
    @Environment(AppContainer.self) private var container
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var palette = container.palette
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { palette.dismiss() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                    TextField("Buscar actividades, materias, contenidos y acciones", text: $palette.query)
                        .textFieldStyle(.plain).font(.title3)
                        .focused($focused)
                        .onSubmit { palette.activateSelected() }
                        .onKeyPress(.upArrow) { palette.move(-1); return .handled }
                        .onKeyPress(.downArrow) { palette.move(1); return .handled }
                        .onKeyPress(.escape) { palette.dismiss(); return .handled }
                    if container.contentIndex.isBuilding || palette.isSearchingContent { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Divider()
                results
                Divider()
                HStack(spacing: 14) {
                    hint("↑↓", "navegar"); hint("↩", "abrir"); hint("esc", "cerrar")
                    Spacer()
                    if !palette.shownContentHits.isEmpty {
                        Button { palette.askAgentAboutResults() } label: {
                            Label("Preguntar a un agente sobre estos resultados", systemImage: "sparkles")
                        }
                        .buttonStyle(.link).keyboardShortcut(.return, modifiers: .command)
                        .help("Adjunta los archivos encontrados al agente de la materia (⌘↩)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .frame(width: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .padding(.top, 110)
        }
        .onAppear { focused = true }
        .onChange(of: container.contentIndex.revision) { _, _ in palette.refreshItems() }
        .onExitCommand { palette.dismiss() }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.caption.monospaced()).padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(text)
        }
    }

    @ViewBuilder
    private var results: some View {
        let palette = container.palette
        if palette.groups.isEmpty {
            Text(palette.query.trimmingCharacters(in: .whitespaces).isEmpty ? "Escriba para buscar." : "Sin resultados.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 28)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        ForEach(palette.groups) { group in
                            Text(group.section.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 2)
                            ForEach(group.items) { item in
                                PaletteRow(item: item, selected: item.id == palette.selectedID,
                                           color: color(for: item))
                                    .id(item.id)
                                    .onTapGesture { palette.activate(item) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 380)
                .onChange(of: palette.selectedID) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private func color(for item: PaletteItem) -> Color {
        guard let folder = item.courseFolder else { return .accentColor }
        return CoursePalette.color(for: container.workspace.snapshot.courses.first { $0.folderName == folder })
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let selected: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).foregroundStyle(color).frame(width: 22)
            if let snippet = item.snippet {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.title).lineLimit(1)
                        Text(item.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    SnippetText(raw: snippet).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text(item.title).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: selected)
    }
}

/// FTS5 snippet with the matched words in bold.
private struct SnippetText: View {
    let raw: String

    var body: some View {
        SnippetParser.segments(from: raw).reduce(Text("")) { partial, segment in
            partial + (segment.isMatch ? Text(segment.text).bold().foregroundStyle(.primary) : Text(segment.text))
        }
    }
}
