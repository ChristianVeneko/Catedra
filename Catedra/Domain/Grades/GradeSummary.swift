import Foundation

enum GradeStatus: Equatable, Sendable {
    case onTrack, atRisk, unreachable, passed

    var label: String {
        switch self {
        case .onTrack: "En camino"
        case .atRisk: "En riesgo"
        case .unreachable: "Inalcanzable"
        case .passed: "Aprobada"
        }
    }
}

/// What the remaining items must yield to reach a target.
struct GradeNeed: Equatable, Sendable {
    /// Points still missing (0 when the target is already met).
    let points: Double
    /// Required average over the remaining points as a fraction (1 = every remaining point); nil when nothing remains.
    let averageFraction: Double?
    let isMet: Bool
    let isReachable: Bool
}

/// Point arithmetic of one subject (UFT accumulates points: each item weighs its maximum). Teacher totals are never "fixed".
struct GradeSummary: Equatable, Sendable {
    let earned: Double
    /// Maximum points of the items already graded (extra credit excluded).
    let gradedPossible: Double
    /// Maximum points of every item that counts.
    let totalPossible: Double
    let targetPercent: Double

    private static let epsilon = 1e-9

    var hasData: Bool { totalPossible > 0 }
    var remaining: Double { Swift.max(0, totalPossible - gradedPossible) }
    var targetPoints: Double { targetPercent / 100 * totalPossible }
    /// Average over graded items; nil while nothing is graded.
    var currentPercentage: Double? { gradedPossible > 0 ? earned / gradedPossible * 100 : nil }
    /// Points earned over the whole subject, as a percentage.
    var accumulatedPercentage: Double? { hasData ? earned / totalPossible * 100 : nil }
    /// Points the subject would end with if the remaining items keep the current average.
    var projectedPoints: Double? { currentPercentage.map { $0 / 100 * totalPossible } }

    var status: GradeStatus {
        guard hasData else { return .onTrack }
        if earned >= targetPoints - Self.epsilon { return .passed }
        if earned + remaining < targetPoints - Self.epsilon { return .unreachable }
        guard let projected = projectedPoints else { return .onTrack }
        return projected >= targetPoints - Self.epsilon ? .onTrack : .atRisk
    }

    func needed(forTargetPercent percent: Double) -> GradeNeed {
        let target = percent / 100 * totalPossible
        let missing = Swift.max(0, target - earned)
        let met = earned >= target - Self.epsilon
        let reachable = earned + remaining >= target - Self.epsilon
        return GradeNeed(points: met ? 0 : missing, averageFraction: remaining > 0 ? (met ? 0 : missing) / remaining : nil,
                         isMet: met, isReachable: reachable)
    }
}

struct CumulativePoint: Equatable, Sendable {
    let date: Date
    let points: Double
}

enum GradeCalculator {
    static func summary(lines: [GradeLine], targetPercent: Double = GradeSettings.defaultTarget) -> GradeSummary {
        let earned = lines.filter(\.countsTowardEarned).reduce(0) { $0 + ($1.earned ?? 0) }
        let possible = lines.filter(\.countsTowardPossible)
        return GradeSummary(earned: earned, gradedPossible: possible.filter(\.isGraded).reduce(0) { $0 + $1.max },
                            totalPossible: possible.reduce(0) { $0 + $1.max }, targetPercent: targetPercent)
    }

    /// Running total of earned points by grading date; lines without a date are left out.
    static func cumulative(lines: [GradeLine]) -> [CumulativePoint] {
        var total = 0.0
        return lines.filter(\.countsTowardEarned).compactMap { line in line.gradedAt.map { (line, $0) } }
            .sorted { $0.1 < $1.1 }
            .map { line, date in
                total += line.earned ?? 0
                return CumulativePoint(date: date, points: total)
            }
    }
}
