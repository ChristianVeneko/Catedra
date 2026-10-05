import Foundation

struct FocusSettings: Codable, Equatable, Sendable {
    static let focusRange = 1...180
    static let breakRange = 1...60

    var focusMinutes = 25
    var breakMinutes = 5

    var clamped: FocusSettings {
        FocusSettings(focusMinutes: min(max(focusMinutes, Self.focusRange.lowerBound), Self.focusRange.upperBound),
                      breakMinutes: min(max(breakMinutes, Self.breakRange.lowerBound), Self.breakRange.upperBound))
    }
}

/// One finished (or stopped) focus period on an activity.
struct FocusSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let activityID: String
    let start: Date
    let end: Date
    let minutes: Int

    init(id: UUID = UUID(), activityID: String, start: Date, end: Date) {
        self.id = id
        self.activityID = activityID
        self.start = start
        self.end = end
        self.minutes = max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
    }
}

/// Pomodoro-style state machine driven by wall-clock dates (never by counting ticks), so sleep, a closed window or a
/// late tick cannot drift it. Pure: the owner calls `advance(now:)` whenever it wakes up.
struct FocusTimer: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable { case focus, rest }

    struct Running: Equatable, Sendable {
        let activityID: String
        var phase: Phase
        var phaseStart: Date
        var phaseEnd: Date
        let breakMinutes: Int
    }

    struct Advance: Equatable, Sendable {
        var sessions: [FocusSession] = []
        var enteredRest = false
        var finishedRest = false
        var isEmpty: Bool { sessions.isEmpty && !enteredRest && !finishedRest }
    }

    /// Focus periods shorter than this are discarded.
    static let minimumLoggedMinutes = 1

    private(set) var running: Running?

    var isRunning: Bool { running != nil }
    var activityID: String? { running?.activityID }
    var phase: Phase? { running?.phase }

    func remaining(now: Date) -> TimeInterval? {
        running.map { max(0, $0.phaseEnd.timeIntervalSince(now)) }
    }

    /// Starts a focus period. A period already running is stopped first and its session returned.
    @discardableResult
    mutating func start(activityID: String, now: Date, settings: FocusSettings) -> FocusSession? {
        let previous = stop(now: now)
        let s = settings.clamped
        running = Running(activityID: activityID, phase: .focus, phaseStart: now,
                          phaseEnd: now.addingTimeInterval(TimeInterval(s.focusMinutes * 60)), breakMinutes: s.breakMinutes)
        return previous
    }

    /// Ends the timer; a focus period of at least one minute is logged up to `now`.
    @discardableResult
    mutating func stop(now: Date) -> FocusSession? {
        defer { running = nil }
        guard let r = running, r.phase == .focus else { return nil }
        return Self.session(activityID: r.activityID, start: r.phaseStart, end: min(max(now, r.phaseStart), r.phaseEnd))
    }

    /// Applies every phase boundary that `now` has passed (focus → rest → idle), logging a finished focus period at
    /// its scheduled end rather than at `now`.
    mutating func advance(now: Date) -> Advance {
        var result = Advance()
        while let r = running, now >= r.phaseEnd {
            switch r.phase {
            case .focus:
                if let session = Self.session(activityID: r.activityID, start: r.phaseStart, end: r.phaseEnd) {
                    result.sessions.append(session)
                }
                running = Running(activityID: r.activityID, phase: .rest, phaseStart: r.phaseEnd,
                                  phaseEnd: r.phaseEnd.addingTimeInterval(TimeInterval(r.breakMinutes * 60)), breakMinutes: r.breakMinutes)
                result.enteredRest = true
            case .rest:
                running = nil
                result.finishedRest = true
            }
        }
        return result
    }

    private static func session(activityID: String, start: Date, end: Date) -> FocusSession? {
        let session = FocusSession(activityID: activityID, start: start, end: end)
        return session.minutes >= minimumLoggedMinutes ? session : nil
    }
}

enum FocusAggregation {
    static func totalMinutes(_ sessions: [FocusSession], activityID: String) -> Int {
        sessions.filter { $0.activityID == activityID }.reduce(0) { $0 + $1.minutes }
    }

    /// Minutes of sessions that started inside `interval`.
    static func minutes(_ sessions: [FocusSession], in interval: DateInterval) -> Int {
        sessions.filter { $0.start >= interval.start && $0.start < interval.end }.reduce(0) { $0 + $1.minutes }
    }

    static func minutesByActivity(_ sessions: [FocusSession], in interval: DateInterval? = nil) -> [String: Int] {
        var result: [String: Int] = [:]
        for s in sessions where interval.map({ s.start >= $0.start && s.start < $0.end }) ?? true { result[s.activityID, default: 0] += s.minutes }
        return result
    }

    /// "45 min", "1 h", "1 h 25 min".
    static func text(minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    /// "12:05" countdown.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "Enfoque real 1 h 10 min de 3 h planificadas"; nil when there is neither.
    static func weekComparisonText(actualMinutes: Int, plannedHours: Double) -> String? {
        let planned = Int((plannedHours * 60).rounded())
        guard actualMinutes > 0 || planned > 0 else { return nil }
        if planned == 0 { return "\(text(minutes: actualMinutes)) de enfoque" }
        return "\(text(minutes: actualMinutes)) de enfoque real · \(text(minutes: planned)) planificadas"
    }
}
