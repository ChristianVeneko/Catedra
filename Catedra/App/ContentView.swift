import SwiftUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var workspace = container.workspace
        @Bindable var sync = container.sync
        NavigationSplitView {
            SidebarView()
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .searchable(text: $workspace.searchText, placement: .toolbar, prompt: "Buscar actividades")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Sincronizar sin archivos") { container.sync.start(includeFiles: false) }
                } label: {
                    Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
                } primaryAction: {
                    container.sync.start(includeFiles: true)
                }
                .help("Sincronizar con SAIA (⌘R)")
            }
        }
        .sheet(isPresented: $sync.isPresented) { SyncSheet() }
        .task {
            await container.workspace.reload()
            if container.settings.pythonPath.isEmpty { await container.settings.detectPython() }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }

    private var isSearching: Bool { !container.workspace.searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    @ViewBuilder
    private var contentColumn: some View {
        let ws = container.workspace
        if isSearching {
            ActivityListView(title: "Resultados", activities: ws.searchResults)
        } else {
            switch container.navigation.sidebar ?? .today {
            case .today: DashboardView()
            case .all: ActivityListView(title: "Todas las actividades", activities: ws.allActivitiesSorted)
            case .activities(let id):
                if let course = course(id) { ActivityListView(title: course.name, activities: ws.activities(in: course)) }
            case .contents(let id):
                if let course = course(id) {
                    ContentTreeView(title: "Contenidos · \(course.name)", nodes: ws.reader.contentTree(root: ws.root, course: course),
                                    emptyText: "Esta materia no tiene contenidos descargados.")
                }
            case .forums(let id):
                if let course = course(id) {
                    ContentTreeView(title: "Foros · \(course.name)", nodes: ws.reader.forums(root: ws.root, course: course),
                                    emptyText: "Esta materia no tiene foros descargados.")
                }
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        let nav = container.navigation
        if isSearching || (nav.sidebar ?? .today).showsActivities {
            if let activity = container.workspace.activity(id: nav.selectedActivityID) {
                ActivityDetailView(activity: activity, container: container).id(activity.id)
            } else {
                ContentUnavailableView("Seleccione una actividad", systemImage: "square.and.pencil",
                                       description: Text("Elija una actividad para ver su enunciado y sus archivos."))
            }
        } else if let url = nav.selectedNodeURL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                ContentUnavailableView("Carpeta", systemImage: "folder", description: Text(url.lastPathComponent))
            } else {
                FilePreviewView(url: url).id(url)
            }
        } else {
            ContentUnavailableView("Seleccione un elemento", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func course(_ id: String) -> Course? { container.workspace.snapshot.courses.first { $0.id == id } }
}
