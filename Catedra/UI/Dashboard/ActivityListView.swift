import SwiftUI

struct ActivityListView: View {
    @Environment(AppContainer.self) private var container
    let title: String
    let activities: [Activity]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if activities.isEmpty {
                        ContentUnavailableView("Sin actividades", systemImage: "tray",
                                               description: Text("No hay actividades que mostrar."))
                    }
                    ForEach(activities) { activity in
                        ActivityCard(activity: activity, course: container.workspace.course(for: activity),
                                     state: container.workspace.state(of: activity, now: context.date),
                                     selected: container.navigation.selectedActivityID == activity.id) {
                            container.navigation.selectedActivityID = activity.id
                        }
                    }
                }
                .padding(20)
                .animation(.snappy, value: activities)
            }
        }
        .navigationTitle(title)
        .navigationSplitViewColumnWidth(min: 380, ideal: 460, max: 640)
    }
}
