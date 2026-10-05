import SwiftUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

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
                Button { container.palette.present() } label: { Label("Buscar", systemImage: "magnifyingglass") }
                    .help("Buscar y ejecutar (⌘K)")
            }
            ToolbarItem(placement: .primaryAction) { RunningAgentsBadge() }
            ToolbarItem(placement: .primaryAction) { ResourceIndicator() }
            ToolbarItem(placement: .primaryAction) { courseAgentButton }
            ToolbarItem(placement: .primaryAction) {
                if container.sync.isRunning {
                    Button { container.sync.isPresented = true } label: {
                        Label("Sincronizando…", systemImage: "arrow.triangle.2.circlepath")
                            .symbolEffect(.rotate, isActive: true)
                    }
                    .help("Sincronizando… (clic para ver el registro)")
                }
            }
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
        .overlay(alignment: .bottom) { SyncBannerView() }
        .overlay {
            if container.palette.isPresented {
                CommandPaletteView().transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy(duration: 0.18), value: container.palette.isPresented)
        .onAppear {
            let open = openWindow
            container.openWindowByID = { open(id: $0) }
        }
        .onOpenURL { container.handle(url: $0) }
        .safeAreaInset(edge: .top, spacing: 0) { setupBanner }
        .task {
            if container.onboarding.consumeAutoPresent() { openWindow(id: "onboarding") }
            await container.onboarding.refreshWarningIfNeeded()
            container.planner.load()
            container.loadTrackingState()
            container.grades.load()
            container.review.load()
            await container.workspace.reload()
            container.widget?.start()
            container.autopilot.pump()
            container.weekly.checkIfDue()
            await container.reminders.refreshPermission()
            container.startLaunchSyncIfNeeded()
            await container.agents.load()
            await container.commands.prepare(folder: container.settings.workspaceURL, provider: container.settings.agentProvider)
            await container.settings.refreshStatus(container.settings.agentProvider)
            if container.settings.pythonPath.isEmpty { await container.settings.detectPython() }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }

    @ViewBuilder
    private var setupBanner: some View {
        if let warning = container.onboarding.setupWarning {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(warning).font(.callout).lineLimit(2)
                Spacer()
                Button("Abrir asistente") { openWindow(id: "onboarding") }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.orange.opacity(0.14))
            .overlay(alignment: .bottom) { Divider() }
        }
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
                AgentProviderLabel("Agente de la materia", provider: container.settings.agentProvider)
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
            case .calendar: CalendarDayListView()
            case .grades: GradesListView()
            case .review: ReviewDecksView()
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
        } else if nav.sidebar == .calendar {
            CalendarView()
        } else if nav.sidebar == .grades {
            GradeDetailView()
        } else if nav.sidebar == .review {
            ReviewDetailView()
        } else if case .agent(let id)? = nav.sidebar, let course = course(id) {
            AgentPanelView(scope: .course(course), color: CoursePalette.color(for: course)).id(course.id)
        } else if let url = nav.selectedNodeURL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                ContentUnavailableView("Carpeta", systemImage: "folder", description: Text(url.lastPathComponent))
            } else {
                FilePreviewView(url: url, initialPage: nav.initialPage(for: url)).id("\(url.path)#\(nav.initialPage(for: url) ?? 0)")
            }
        } else {
            ContentUnavailableView("Seleccione un elemento", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func course(_ id: String) -> Course? { container.workspace.snapshot.courses.first { $0.id == id } }
}
