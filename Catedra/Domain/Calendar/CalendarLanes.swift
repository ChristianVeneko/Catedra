import Foundation

/// Side-by-side placement of overlapping timed entries within one day column. Pure.
struct LanedEntry: Equatable, Sendable {
    let entry: CalendarEntry
    let lane: Int
    let laneCount: Int
}

enum CalendarLanes {
    static let defaultDuration: TimeInterval = 3600

    static func assign(_ entries: [CalendarEntry]) -> [LanedEntry] {
        let sorted = entries.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        var result: [LanedEntry] = []
        var cluster: [(entry: CalendarEntry, lane: Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(laneEnds.count, 1)
            result += cluster.map { LanedEntry(entry: $0.entry, lane: $0.lane, laneCount: count) }
            cluster = []
            laneEnds = []
        }

        for entry in sorted {
            let end = entry.end.flatMap { $0 > entry.start ? $0 : nil } ?? entry.start.addingTimeInterval(defaultDuration)
            if entry.start >= clusterEnd { flush() }
            let lane = laneEnds.firstIndex { $0 <= entry.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            cluster.append((entry, lane))
            clusterEnd = max(clusterEnd, end)
        }
        flush()
        return result
    }
}
