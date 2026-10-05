import SwiftUI

struct SidebarView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var nav = container.navigation
        List(selection: $nav.sidebar) {
            Section {
                Label("Hoy", systemImage: "sun.max").tag(SidebarItem.today)
                Label("Calendario", systemImage: "calendar").tag(SidebarItem.calendar)
                Label("Notas", systemImage: "chart.bar.doc.horizontal").tag(SidebarItem.grades)
                Label("Repaso", systemImage: "rectangle.on.rectangle")
                    .badge(container.review.todayCount(today: ReviewDay(date: container.clock.now)))
                    .tag(SidebarItem.review)
                Label("Todas las actividades", systemImage: "tray.full").tag(SidebarItem.all)
            }
            Section("Materias") {
                ForEach(container.workspace.snapshot.courses) { course in
                    CourseDisclosure(course: course)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
    }
}

private struct CourseDisclosure: View {
    @Environment(AppContainer.self) private var container
    let course: Course
    @State private var expanded = false

    var body: some View {
        let color = CoursePalette.color(for: course)
        DisclosureGroup(isExpanded: $expanded) {
            Label("Actividades", systemImage: "checklist").tag(SidebarItem.activities(course.id))
            Label("Contenidos", systemImage: "folder").tag(SidebarItem.contents(course.id))
            Label("Foros", systemImage: "bubble.left.and.bubble.right").tag(SidebarItem.forums(course.id))
            Label {
                HStack {
                    Text("Agente")
                    Spacer()
                    let running = container.agents.runningProviders(scopeID: course.id)
                    if !running.isEmpty { AgentActivityDot(providers: running) }
                }
            } icon: { AgentProviderMark(provider: container.settings.agentProvider, size: 14) }
            .tag(SidebarItem.agent(course.id))
        } label: {
            Label {
                HStack(spacing: 6) {
                    Text(course.name).lineLimit(1)
                    Spacer(minLength: 0)
                    let running = container.agents.runningProviders(inCourse: course.folderName)
                    if !running.isEmpty { AgentActivityDot(providers: running) }
                }
            } icon: {
                Image(systemName: CoursePalette.symbol(for: course))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .contextMenu { AutopilotCourseMenu(course: course) }
        }
    }
}

/// Per-course choice for the new-activity autopilot (context menu of the course).
struct AutopilotCourseMenu: View {
    @Environment(AppContainer.self) private var container
    let course: Course

    var body: some View {
        let current = container.settings.autopilotOverride(forCourse: course.folderName)
        Menu("Piloto automático") {
            ForEach(AutopilotOverride.allCases, id: \.self) { option in
                Button {
                    container.settings.setAutopilotOverride(option, forCourse: course.folderName)
                } label: {
                    if option == current { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
            Divider()
            Text("Ejecuta agentes automáticamente y consume créditos.")
        }
    }
}
