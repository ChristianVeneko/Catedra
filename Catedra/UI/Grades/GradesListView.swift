import SwiftUI

/// Content column of the "Notas" destination: one row per subject.
struct GradesListView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var grades = container.grades
        let snapshot = container.workspace.snapshot
        let subjects = grades.subjects(in: snapshot)
        let suggestions = grades.suggestions(in: snapshot)
        List(selection: $grades.selectedSubjectID) {
            if !suggestions.isEmpty {
                Section("Sugerencias") {
                    ForEach(suggestions, id: \.courseKeys) { suggestion in
                        SuggestionRow(suggestion: suggestion, courses: grades.courseRefs(in: snapshot))
                    }
                }
            }
            Section {
                ForEach(subjects) { item in
                    SubjectRow(item: item, color: GradeSubjects.color(for: item.subject, courses: snapshot.courses))
                        .tag(item.id)
                }
            }
        }
        .overlay {
            if subjects.isEmpty {
                ContentUnavailableView("Sin notas todavía", systemImage: "chart.bar.doc.horizontal",
                                       description: Text("Sincronice con SAIA para descargar el libro de calificaciones de cada materia."))
            }
        }
        .navigationTitle("Notas")
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        .toolbar {
            ToolbarItem {
                Button { grades.isGroupingPresented = true } label: { Label("Agrupar materias", systemImage: "rectangle.3.group") }
                    .help("Unir materias (por ejemplo teoría y laboratorio) en una sola")
            }
        }
        .sheet(isPresented: $grades.isGroupingPresented) { GradeGroupingSheet().environment(container) }
    }
}

private struct SubjectRow: View {
    let item: SubjectGrades
    let color: Color

    var body: some View {
        let summary = item.summary
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 18)
                Text(item.subject.name).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                GradeStatusBadge(status: summary.status)
            }
            GradeProgressBar(summary: summary, tint: color)
            HStack {
                Text("\(GradeFormat.points(summary.earned)) / \(GradeFormat.points(summary.totalPossible)) pts").font(.callout.monospacedDigit())
                Spacer()
                if let current = summary.currentPercentage {
                    Text("\(GradeFormat.percent(current)) de lo calificado").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Sin calificar").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SuggestionRow: View {
    @Environment(AppContainer.self) private var container
    let suggestion: SubjectSuggestion
    let courses: [GradeCourseRef]

    var body: some View {
        let names = suggestion.courseKeys.compactMap { key in courses.first { $0.key == key }?.name }
        VStack(alignment: .leading, spacing: 6) {
            Label("¿Es una sola materia?", systemImage: "lightbulb").font(.subheadline.weight(.semibold))
            Text(names.joined(separator: " + ")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Unir") { container.grades.group(suggestion.courseKeys) }.controlSize(.small)
                Button("Descartar") { container.grades.dismiss(suggestion) }.controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
