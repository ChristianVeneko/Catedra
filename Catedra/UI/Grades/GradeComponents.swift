import SwiftUI

extension GradeStatus {
    var tint: Color {
        switch self {
        case .onTrack: .blue
        case .atRisk: .orange
        case .unreachable: .red
        case .passed: .green
        }
    }

    var symbol: String {
        switch self {
        case .onTrack: "arrow.up.right.circle.fill"
        case .atRisk: "exclamationmark.triangle.fill"
        case .unreachable: "xmark.octagon.fill"
        case .passed: "checkmark.seal.fill"
        }
    }
}

struct GradeStatusBadge: View {
    let status: GradeStatus
    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.14), in: Capsule())
    }
}

/// Earned points (solid), graded-but-lost points (light) and the pending rest, with a marker at the target.
struct GradeProgressBar: View {
    let summary: GradeSummary
    var tint: Color
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let total = max(summary.totalPossible, 0.0001)
            let earned = min(summary.earned, summary.totalPossible) / total
            let graded = min(summary.gradedPossible, summary.totalPossible) / total
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint.opacity(0.28)).frame(width: geo.size.width * graded)
                Capsule().fill(tint).frame(width: geo.size.width * earned)
                Rectangle().fill(Color.primary.opacity(0.55)).frame(width: 2, height: height + 6)
                    .offset(x: geo.size.width * min(1, summary.targetPercent / 100) - 1)
            }
            .frame(height: height).frame(maxHeight: .infinity)
        }
        .frame(height: height + 6)
        .accessibilityElement()
        .accessibilityLabel("\(GradeFormat.points(summary.earned)) de \(GradeFormat.points(summary.totalPossible)) puntos")
    }
}

extension GradeLine {
    var statusText: String {
        if excluded { return "No cuenta" }
        if isExtra { return isGraded ? "Extra" : "Extra pendiente" }
        if isMakeup { return isGraded ? "Calificada (diferido)" : "Diferido: no cuenta" }
        return isGraded ? "Calificada" : "Pendiente"
    }

    var statusTint: Color {
        if excluded || (isMakeup && !isGraded) { return .secondary }
        return isGraded ? .green : .orange
    }
}

extension GradeSubjects {
    static func color(for subject: GradeSubject, courses: [Course]) -> Color {
        CoursePalette.color(for: courses.first { subject.courseKeys.contains($0.folderName) })
    }
}

/// Namespace for small helpers shared by the grades views.
enum GradeSubjects {}
