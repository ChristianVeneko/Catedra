import SwiftUI
import WidgetKit

@main
struct CatedraWidgetBundle: Widget {
    let kind = "CatedraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CatedraProvider()) { entry in
            CatedraWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Cátedra")
        .description("Próximas entregas, tarjetas de repaso para hoy y enfoque en curso.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CatedraEntry: TimelineEntry {
    let date: Date
    /// Nil when the app has not written a snapshot yet.
    let snapshot: WidgetSnapshot?

    var isOutdated: Bool { snapshot?.isStale(at: date) ?? true }
    var deliveries: [WidgetSnapshot.Delivery] { snapshot?.deliveries(at: date) ?? [] }
    var cardsDue: Int { snapshot?.cardsDue ?? 0 }
    var focus: WidgetSnapshot.Focus? { snapshot?.focus(at: date) }
}

struct CatedraProvider: TimelineProvider {
    private let store = WidgetSnapshotStore.appGroup

    func placeholder(in context: Context) -> CatedraEntry {
        let now = Date()
        let sample = WidgetSnapshot(
            generatedAt: now,
            deliveries: [.init(id: "sample", name: "Tarea 1", courseName: "Materia", due: now.addingTimeInterval(86_400), colorHex: "#5C6BF5")],
            cardsDue: 12, focus: nil)
        return CatedraEntry(date: now, snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (CatedraEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : CatedraEntry(date: Date(), snapshot: store.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatedraEntry>) -> Void) {
        let now = Date()
        let snapshot = store.read()
        guard let snapshot else {
            completion(Timeline(entries: [CatedraEntry(date: now, snapshot: nil)], policy: .after(now.addingTimeInterval(1800))))
            return
        }
        var dates = WidgetTimelinePlanner.entryDates(now: now, snapshot: snapshot)
        // One more entry when the snapshot turns stale, so the placeholder message appears without the app running.
        let staleDate = snapshot.generatedAt.addingTimeInterval(WidgetSnapshot.staleInterval + 1)
        if staleDate > now, staleDate <= (dates.last ?? now) { dates.append(staleDate) }
        let entries = dates.sorted().map { CatedraEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(1800))))
    }
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { self = .accentColor; return }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

struct CatedraWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CatedraEntry

    var body: some View {
        Group {
            if entry.isOutdated {
                outdated
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .widgetURL(primaryLink)
    }

    /// Small widgets support a single tap target (`Link` is ignored), so it opens the next delivery when there is one.
    private var primaryLink: URL {
        if family == .systemSmall, !entry.isOutdated, let next = entry.deliveries.first { return WidgetLink.activity(next.id).url }
        return WidgetLink.open.url
    }

    private var outdated: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundStyle(.secondary)
            Text("Abre Cátedra para actualizar").font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Próxima entrega").font(.caption2).foregroundStyle(.secondary)
            if let next = entry.deliveries.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.name).font(.headline).lineLimit(2)
                    Text(next.courseName).font(.caption).foregroundStyle(Color(hex: next.colorHex)).lineLimit(1)
                    Text(next.due, style: .relative).font(.callout.monospacedDigit()).foregroundStyle(.primary)
                }
            } else {
                Text("Sin entregas pendientes").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            cardsLabel(linked: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Próximas entregas").font(.caption2).foregroundStyle(.secondary)
                if entry.deliveries.isEmpty {
                    Text("Sin entregas pendientes").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(entry.deliveries.prefix(3)) { delivery in
                    Link(destination: WidgetLink.activity(delivery.id).url) {
                        HStack(spacing: 6) {
                            Capsule().fill(Color(hex: delivery.colorHex)).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(delivery.name).font(.footnote.weight(.semibold)).lineLimit(1)
                                Text(delivery.courseName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(delivery.due, style: .relative).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing)
                                .frame(maxWidth: 70, alignment: .trailing)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                cardsLabel(linked: true)
                if let focus = entry.focus {
                    VStack(alignment: .leading, spacing: 1) {
                        Label("Enfoque", systemImage: "timer").font(.caption2).foregroundStyle(.secondary)
                        Text(focus.activityName).font(.footnote.weight(.semibold)).lineLimit(2)
                        Text(focus.endsAt, style: .timer).font(.callout.monospacedDigit())
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 110, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cardsLabel(linked: Bool) -> some View {
        let label = Label(entry.cardsDue == 0 ? "Sin tarjetas para hoy" : "\(entry.cardsDue) tarjetas para hoy", systemImage: "rectangle.stack")
            .font(.caption.weight(.medium))
            .foregroundStyle(entry.cardsDue == 0 ? Color.secondary : Color.accentColor)
        if linked { Link(destination: WidgetLink.review.url) { label } } else { label }
    }
}
