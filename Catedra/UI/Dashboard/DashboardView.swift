import SwiftUI

struct DashboardView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let agenda = container.workspace.agenda(now: context.date)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    if let hero = agenda.hero { HeroCard(activity: hero) }
                    if !agenda.overdue.isEmpty {
                        SectionHeader(title: "Vencidas", count: agenda.overdue.count)
                        cards(agenda.overdue, now: context.date)
                    }
                    SectionHeader(title: "Próximos 14 días")
                    if agenda.days.isEmpty {
                        Text("No hay actividades con fecha en los próximos 14 días.")
                            .foregroundStyle(.secondary).padding(.vertical, 6)
                    }
                    ForEach(agenda.days) { group in
                        Text(Formatters.dayHeader(group.day))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                        cards(group.activities, now: context.date)
                    }
                    if !agenda.later.isEmpty {
                        SectionHeader(title: "Más adelante", count: agenda.later.count)
                        cards(agenda.later, now: context.date)
                    }
                    if !agenda.undated.isEmpty {
                        SectionHeader(title: "Sin fecha", count: agenda.undated.count)
                        cards(agenda.undated, now: context.date)
                    }
                }
                .padding(20)
                .animation(.snappy, value: agenda)
            }
        }
        .navigationTitle("Hoy")
        .navigationSplitViewColumnWidth(min: 380, ideal: 460, max: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Formatters.greeting()).font(.largeTitle.weight(.bold))
            if let last = container.workspace.snapshot.lastSync {
                Text("Última sincronización: \(Formatters.relative(last))").foregroundStyle(.secondary)
            } else {
                Text("Aún no hay datos sincronizados.").foregroundStyle(.secondary)
            }
            if let error = container.workspace.loadError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            }
        }
    }

    private func cards(_ items: [Activity], now: Date) -> some View {
        ForEach(items) { activity in
            ActivityCard(activity: activity, course: container.workspace.course(for: activity),
                         state: container.workspace.state(of: activity, now: now),
                         selected: container.navigation.selectedActivityID == activity.id) {
                container.navigation.selectedActivityID = activity.id
            }
        }
    }
}

private struct HeroCard: View {
    @Environment(AppContainer.self) private var container
    let activity: Activity

    var body: some View {
        let course = container.workspace.course(for: activity)
        let color = CoursePalette.color(for: course)
        Button { container.navigation.selectedActivityID = activity.id } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label("Siguiente entrega", systemImage: "flame.fill")
                    .font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.white.opacity(0.85))
                Text(activity.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.leading).lineLimit(3)
                Text("\(activity.courseName) · \(activity.kind.displayName)").foregroundStyle(.white.opacity(0.85))
                HStack(alignment: .lastTextBaseline) {
                    if let due = activity.due {
                        CountdownText(due: due, font: .system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(Formatters.due(due)).font(.callout).foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: color.opacity(0.35), radius: 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
