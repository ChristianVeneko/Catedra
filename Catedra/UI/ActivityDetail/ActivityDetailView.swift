import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers

struct ActivityDetailView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: ActivityDetailModel
    @State private var quickLookURL: URL?
    @State private var showImporter = false
    @State private var isDropTargeted = false

    init(activity: Activity, container: AppContainer) {
        _model = State(initialValue: ActivityDetailModel(
            activity: activity, root: container.workspace.root, reader: container.reader,
            importer: container.importFiles, onChange: { await container.workspace.reload() }))
    }

    var body: some View {
        @Bindable var nav = container.navigation
        Group {
            if nav.activityTab == .agent {
                let color = CoursePalette.color(for: container.workspace.course(for: model.activity))
                AgentPanelView(scope: .activity(model.activity), color: color)
                    .navigationTitle(model.activity.name)
            } else {
                detailContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Vista", selection: $nav.activityTab) {
                    Text("Detalle").tag(ActivityDetailTab.detail)
                    Label("Agente", systemImage: "sparkles").tag(ActivityDetailTab.agent)
                }
                .pickerStyle(.segmented).frame(width: 200)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        let activity = model.activity
        let course = container.workspace.course(for: activity)
        let color = CoursePalette.color(for: course)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(activity, course: course, color: color)
                if let statement = model.statement {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Enunciado")
                        MarkdownView(source: statement, skipFirstHeading: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                }
                dropZone(color: color)
                fileSection("Material", systemImage: "books.vertical", urls: model.files.material)
                fileSection("Entrega", systemImage: "paperplane", urls: model.files.entrega)
                fileSection("Preparación", systemImage: "pencil.and.list.clipboard", urls: model.files.preparacion)
                fileSection("Apuntes", systemImage: "note.text", urls: model.files.apuntes)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(activity.name)
        .quickLookPreview($quickLookURL, in: allFiles)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.importFiles(urls) } }
        }
        .task(id: container.workspace.snapshot.lastSync) { model.reload() }
    }

    private var allFiles: [URL] {
        model.files.material + model.files.entrega + model.files.preparacion + model.files.apuntes
    }

    // MARK: - Pieces

    private func header(_ activity: Activity, course: Course?, color: Color) -> some View {
        let state = container.workspace.state(of: activity)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: activity.kind.symbolName).foregroundStyle(color)
                Text("\(activity.courseName) · \(activity.kind.displayName)").foregroundStyle(.secondary)
                Spacer()
                StatusBadge(state: state)
            }
            Text(activity.name).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                if let due = activity.due {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fecha límite").font(.caption).foregroundStyle(.secondary)
                        Text(Formatters.due(due)).font(.headline)
                    }
                    if state != .submitted { CountdownText(due: due, font: .system(size: 28, weight: .bold, design: .rounded)) }
                } else {
                    Text("Sin fecha límite").foregroundStyle(.secondary)
                }
                Spacer()
                if activity.hasGrade { Label(activity.grade, systemImage: "star.fill").foregroundStyle(.yellow) }
            }
            HStack {
                if let url = activity.url {
                    Link(destination: url) { Label("Abrir en SAIA", systemImage: "safari") }
                        .buttonStyle(.borderedProminent).tint(color)
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.folderURL]) } label: {
                    Label("Mostrar en Finder", systemImage: "folder")
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: color)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).padding(.vertical, 14)
        }
    }

    private func dropZone(color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 28)).foregroundStyle(color)
            Text("Arrastre archivos aquí para copiarlos").font(.headline)
            Picker("Destino", selection: $model.importTarget) {
                ForEach(ImportTarget.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 340)
            Button("Elegir archivos…") { showImporter = true }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(model.isError ? .red : .secondary)
            }
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(isDropTargeted ? color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(isDropTargeted ? 0.9 : 0.4),
                                                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .animation(.snappy, value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.importFiles(urls.filter(\.isFileURL)) }
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    @ViewBuilder
    private func fileSection(_ title: String, systemImage: String, urls: [URL]) -> some View {
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage).font(.title3.weight(.semibold))
                VStack(spacing: 0) {
                    ForEach(urls, id: \.self) { url in
                        FileRow(url: url, preview: { quickLookURL = url })
                        if url != urls.last { Divider().padding(.leading, 46) }
                    }
                }
                .card()
            }
        }
    }
}

struct FileRow: View {
    let url: URL
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(sizeText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: preview) { Image(systemName: "eye") }.help("Vista previa")
            Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.app") }.help("Abrir")
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }.help("Mostrar en Finder")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Vista previa", action: preview)
            Button("Abrir") { NSWorkspace.shared.open(url) }
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private var sizeText: String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) : "Carpeta o vacío"
    }
}
