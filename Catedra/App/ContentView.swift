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
            ToolbarItem(placement: .primaryAction) { RunningAgentsBadge() }
            ToolbarItem(placement: .primaryAction) { courseAgentButton }
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
            await container.agents.load()
            if container.settings.claudePath.isEmpty { await container.settings.detectClaude() }
            if container.settings.pythonPath.isEmpty { await container.settings.detectPython() }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }

    /// Course the user is currently looking at (sidebar course item or selected activity).
    private var currentCourse: Course? {
        let nav = container.navigation
        if let id = nav.sidebar?.courseID { return course(id) }
        return container.workspace.activity(id: nav.selectedActivityID).flatMap { container.workspace.course(for: $0) }
    }

    @ViewBuilder
    private var courseAgentButton: some View {
        if let course = currentCourse {
            Button { container.navigation.sidebar = .agent(course.id) } label: {
                Label("Agente de la materia", systemImage: "sparkles")
            }
            .help("Abrir el agente de «\(course.name)»")
        }
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
            case .agent(let id):
                if let course = course(id) {
                    AgentHistoryListView(scope: .course(course), color: CoursePalette.color(for: course))
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
        } else if case .agent(let id)? = nav.sidebar, let course = course(id) {
            AgentPanelView(scope: .course(course), color: CoursePalette.color(for: course)).id(course.id)
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
