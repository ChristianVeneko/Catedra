import SwiftUI

extension ActivityState {
    var tint: Color {
        switch self {
        case .pending: .orange
        case .inProgress: .blue
        case .upcoming: .gray
        case .submitted: .green
        case .overdue: .red
        }
    }
}

struct StatusBadge: View {
    let state: ActivityState
    var body: some View {
        Text(state.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(state.tint)
            .background(state.tint.opacity(0.14), in: Capsule())
    }
}

/// Rounded material container used across the app.
struct CardBackground: ViewModifier {
    var tint: Color? = nil
    var selected = false
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? (tint ?? .accentColor) : Color.primary.opacity(0.07), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

extension View {
    func card(tint: Color? = nil, selected: Bool = false) -> some View {
        modifier(CardBackground(tint: tint, selected: selected))
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.title3.weight(.semibold))
            if let count {
                Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(.quaternary, in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 6)
    }
}

/// Live countdown text, refreshed every minute.
struct CountdownText: View {
    let due: Date
    var font: Font = .system(.body, design: .rounded)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let text = CountdownFormatter.text(until: due, from: context.date)
            Text(text)
                .font(font.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(text == "Vencida" ? Color.red : Color.primary)
                .contentTransition(.numericText())
        }
    }
}

struct ActivityCard: View {
    @Environment(AppContainer.self) private var container
    let activity: Activity
    let course: Course?
    let state: ActivityState
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(CoursePalette.color(for: course)).frame(width: 4)
                Image(systemName: activity.kind.symbolName)
                    .font(.title3).frame(width: 28)
                    .foregroundStyle(CoursePalette.color(for: course))
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(activity.courseName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let due = activity.due {
                        Text(Formatters.due(due)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Sin fecha").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        let running = container.agents.runningProviders(scopeID: activity.id)
                        if !running.isEmpty { AgentActivityDot(providers: running) }
                        StatusBadge(state: state)
                    }
                    ActivityFlagBadges(activityID: activity.id)
                    if let due = activity.due, state != .submitted { CountdownText(due: due, font: .system(.caption, design: .rounded)) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .card(tint: CoursePalette.color(for: course), selected: selected)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
