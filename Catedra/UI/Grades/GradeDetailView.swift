import Charts
import SwiftUI

/// Detail column of the "Notas" destination: totals, simulator, chart and the item table of one subject.
struct GradeDetailView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let snapshot = container.workspace.snapshot
        let subjects = container.grades.subjects(in: snapshot)
        if let item = subjects.first(where: { $0.id == container.grades.selectedSubjectID }) {
            SubjectGradesView(item: item, color: GradeSubjects.color(for: item.subject, courses: snapshot.courses))
                .id(item.id)
        } else {
            ContentUnavailableView("Seleccione una materia", systemImage: "chart.bar.doc.horizontal",
                                   description: Text("Vea sus puntos, lo que falta y cuánto necesita para aprobar."))
        }
    }
}

private struct SubjectGradesView: View {
    @Environment(AppContainer.self) private var container
    let item: SubjectGrades
    let color: Color

    var body: some View {
        let summary = item.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(summary)
                GradeProgressBar(summary: summary, tint: color, height: 14)
                metrics(summary)
                SimulatorCard(subjectID: item.subject.id, summary: summary)
                chart(summary)
                table
            }
            .padding(20).frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle(item.subject.name)
    }

    private func header(_ summary: GradeSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.subject.name).font(.largeTitle.weight(.semibold))
                if item.subject.courseKeys.count > 1 {
                    Text("Materias unidas: " + item.subject.courseKeys.map { key in
                        container.grades.courseRefs(in: container.workspace.snapshot).first { $0.key == key }?.name ?? key
                    }.joined(separator: " + ")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            GradeStatusBadge(status: summary.status)
        }
    }

    private func metrics(_ summary: GradeSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            metric("Acumulado", "\(GradeFormat.points(summary.earned)) / \(GradeFormat.points(summary.totalPossible)) pts",
                   summary.accumulatedPercentage.map(GradeFormat.percent) ?? "")
            metric("Promedio actual", summary.currentPercentage.map(GradeFormat.percent) ?? "—",
                   "de \(GradeFormat.points(summary.gradedPossible)) pts calificados")
            metric("Proyección", summary.projectedPoints.map { "\(GradeFormat.points($0)) pts" } ?? "—", "si mantiene su promedio")
            metric("Por evaluar", "\(GradeFormat.points(summary.remaining)) pts", "meta: \(GradeFormat.points(summary.targetPoints)) pts")
        }
    }

    private func metric(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).card()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(_ summary: GradeSummary) -> some View {
        let points = GradeCalculator.cumulative(lines: item.lines)
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Puntos acumulados").font(.headline)
                Chart {
                    ForEach(points, id: \.date) { point in
                        LineMark(x: .value("Fecha", point.date), y: .value("Puntos", point.points))
                            .interpolationMethod(.stepEnd).foregroundStyle(color)
                        PointMark(x: .value("Fecha", point.date), y: .value("Puntos", point.points)).foregroundStyle(color)
                    }
                    RuleMark(y: .value("Meta", summary.targetPoints))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.green)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Meta \(GradeFormat.points(summary.targetPoints)) pts").font(.caption2).foregroundStyle(.green)
                        }
                }
                .chartYScale(domain: 0...max(summary.totalPossible, summary.earned, 1))
                .frame(height: 180)
            }
            .padding(14).card()
        }
    }

    // MARK: - Items

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Evaluaciones").font(.headline).padding(.bottom, 8)
            row(name: "Nombre", grade: "Nota", max: "Máximo", status: "Estado", toggle: nil, header: true)
            Divider()
            ForEach(item.lines) { line in
                row(name: line.name, grade: line.earned.map(GradeFormat.points) ?? "—", max: GradeFormat.points(line.max),
                    status: line.statusText, toggle: line, header: false)
                    .opacity(line.excluded ? 0.55 : 1)
                Divider().opacity(0.4)
            }
            Text("Diferidos y sustitutivos no suman puntos posibles hasta que se califican. Si uno reemplaza un examen, marque ese examen como «No cuenta».")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }
        .padding(14).card()
    }

    private func row(name: String, grade: String, max: String, status: String, toggle line: GradeLine?, header: Bool) -> some View {
        HStack(spacing: 10) {
            Text(name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text(grade).monospacedDigit().frame(width: 60, alignment: .trailing)
            Text(max).monospacedDigit().frame(width: 60, alignment: .trailing)
            Group {
                if let line {
                    Text(status).font(.caption.weight(.semibold)).foregroundStyle(line.statusTint)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(line.statusTint.opacity(0.14), in: Capsule())
                } else { Text(status) }
            }
            .frame(width: 150, alignment: .leading)
            Group {
                if let line {
                    Toggle("No cuenta", isOn: Binding(get: { line.excluded }, set: { _ in container.grades.toggleExcluded(line.id) }))
                        .toggleStyle(.checkbox).font(.caption)
                } else { Text("") }
            }
            .frame(width: 90, alignment: .leading)
        }
        .font(header ? .caption.weight(.semibold) : .callout)
        .foregroundStyle(header ? .secondary : .primary)
        .padding(.vertical, header ? 4 : 6)
        .help(line.map { $0.feedback.isEmpty ? $0.name : $0.feedback } ?? "")
    }
}

/// "¿Cuánto necesito?": target in percent of the subject total and the required average over what is left.
private struct SimulatorCard: View {
    @Environment(AppContainer.self) private var container
    let subjectID: String
    let summary: GradeSummary
    @State private var target: Double

    init(subjectID: String, summary: GradeSummary) {
        self.subjectID = subjectID
        self.summary = summary
        _target = State(initialValue: summary.targetPercent)
    }

    var body: some View {
        let need = summary.needed(forTargetPercent: target)
        VStack(alignment: .leading, spacing: 10) {
            Text("¿Cuánto necesito?").font(.headline)
            HStack(spacing: 12) {
                Text("Meta").foregroundStyle(.secondary)
                Slider(value: $target, in: 0...100, step: 5) { editing in
                    if !editing { container.grades.setTarget(target, forSubject: subjectID) }
                }
                Text("\(GradeFormat.points(target)) % · \(GradeFormat.points(target / 100 * summary.totalPossible)) pts")
                    .monospacedDigit().frame(width: 130, alignment: .trailing)
                Stepper("", value: $target, in: 0...100, step: 1) { _ in container.grades.setTarget(target, forSubject: subjectID) }
                    .labelsHidden()
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: need.isMet ? "checkmark.circle.fill" : (need.isReachable ? "target" : "xmark.octagon.fill"))
                    .foregroundStyle(need.isMet ? .green : (need.isReachable ? Color.accentColor : .red))
                Text(GradeNeedText.describe(summary: summary, targetPercent: target)).font(.callout)
            }
            Text("Por defecto la meta es 50 % del total. Se guarda por materia.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
