import Foundation

// Compiled into both the Catedra app and the CatedraWidget extension: the app writes the snapshot, the widget reads it.
// Keep this file free of app-only types.

/// What the desktop widget displays. Small and self-contained so the extension never needs the workspace.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Delivery: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let courseName: String
        let due: Date
        /// Course accent color as `#RRGGBB`.
        let colorHex: String
    }

    struct Focus: Codable, Equatable, Sendable {
        let activityName: String
        let endsAt: Date
    }

    /// Snapshots older than this are shown as outdated.
    static let staleInterval: TimeInterval = 24 * 3600

    let generatedAt: Date
    let deliveries: [Delivery]
    let cardsDue: Int
    let focus: Focus?

    func isStale(at date: Date) -> Bool { date.timeIntervalSince(generatedAt) > Self.staleInterval }

    /// Deliveries still upcoming at `date` (the snapshot may be older than the timeline entry).
    func deliveries(at date: Date) -> [Delivery] { deliveries.filter { $0.due > date } }

    /// The focus session if it is still running at `date`.
    func focus(at date: Date) -> Focus? {
        guard let focus, focus.endsAt > date else { return nil }
        return focus
    }

    /// Equality ignoring `generatedAt`, to avoid rewriting the file and reloading timelines for nothing.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        deliveries == other.deliveries && cardsDue == other.cardsDue && focus == other.focus
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    func encoded() throws -> Data { try Self.makeEncoder().encode(self) }

    static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}

enum WidgetSnapshotBuilder {
    static let maxDeliveries = 3

    /// An activity reduced to what the widget needs.
    struct Candidate: Equatable, Sendable {
        let id: String
        let name: String
        let courseName: String
        let due: Date?
        let isSubmitted: Bool
        let colorHex: String
    }

    /// Top upcoming not-submitted deliveries (undated and overdue ones are left out), soonest first.
    static func build(now: Date, candidates: [Candidate], cardsDue: Int, focus: WidgetSnapshot.Focus?) -> WidgetSnapshot {
        let upcoming = candidates
            .compactMap { c -> WidgetSnapshot.Delivery? in
                guard !c.isSubmitted, let due = c.due, due > now else { return nil }
                return WidgetSnapshot.Delivery(id: c.id, name: c.name, courseName: c.courseName, due: due, colorHex: c.colorHex)
            }
            .enumerated()
            .sorted { ($0.element.due, $0.offset) < ($1.element.due, $1.offset) }
            .map(\.element)
        return WidgetSnapshot(generatedAt: now, deliveries: Array(upcoming.prefix(maxDeliveries)), cardsDue: max(0, cardsDue), focus: focus)
    }
}

/// Dates at which the widget timeline should produce an entry.
enum WidgetTimelinePlanner {
    static let step: TimeInterval = 30 * 60

    /// `now`, every 30 minutes up to `horizon`, and the moments a delivery falls due or the focus session ends.
    static func entryDates(now: Date, snapshot: WidgetSnapshot, horizon: TimeInterval = 3 * 3600) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]
        var t = now.addingTimeInterval(step)
        while t <= end {
            dates.insert(t)
            t = t.addingTimeInterval(step)
        }
        var special = snapshot.deliveries.map(\.due)
        if let focus = snapshot.focus { special.append(focus.endsAt) }
        for date in special where date > now && date <= end { dates.insert(date) }
        return dates.sorted()
    }
}

/// `catedra://` links the widget opens in the app.
enum WidgetLink: Equatable {
    static let scheme = "catedra"

    case open
    case review
    case activity(String)

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .open: components.host = "open"
        case .review: components.host = "review"
        case .activity(let id):
            components.host = "activity"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        }
        return components.url ?? URL(string: "\(Self.scheme)://open")!
    }

    static func parse(_ url: URL) -> WidgetLink? {
        guard url.scheme == scheme, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.host {
        case "open": return .open
        case "review": return .review
        case "activity":
            guard let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty else { return nil }
            return .activity(id)
        default: return nil
        }
    }
}

/// Reads and writes `widget-snapshot.json` in a directory (the app group container in production).
struct WidgetSnapshotStore: Sendable {
    static let appGroupID = "28U4T9UK9R.com.cmendoza.catedra"
    static let fileName = "widget-snapshot.json"

    let directory: URL?

    init(directory: URL?) { self.directory = directory }

    /// Store backed by the shared app group container; `directory` is nil when the group is not available.
    static var appGroup: WidgetSnapshotStore {
        WidgetSnapshotStore(directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID))
    }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }

    func write(_ snapshot: WidgetSnapshot) throws {
        guard let directory, let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try snapshot.encoded().write(to: url, options: .atomic)
    }
}

/// Limits how often the app asks WidgetKit to reload.
struct WidgetReloadThrottle: Sendable {
    let minimumInterval: TimeInterval
    private var last: Date?

    init(minimumInterval: TimeInterval = 30) { self.minimumInterval = minimumInterval }

    /// True (and records `now`) when enough time has passed since the previous allowed reload.
    mutating func shouldReload(now: Date) -> Bool {
        if let last, now.timeIntervalSince(last) < minimumInterval { return false }
        last = now
        return true
    }
}

/// Course accent colors as hex; mirrors `CoursePalette` (the widget cannot import the app's SwiftUI palette).
enum WidgetCourseColor {
    static let hexes = ["#5C6BF5", "#1FA89E", "#ED7338", "#D94C85", "#4CB04F", "#9E61E6", "#E6AD1A", "#2999E6", "#D1474C"]

    static func hex(forCourseNumber number: Int) -> String {
        hexes[(number - 1 + hexes.count * 4) % hexes.count]
    }
}
