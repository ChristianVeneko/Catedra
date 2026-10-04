import SwiftUI

/// Merge courses that SAIA splits into several classrooms (theory + laboratory) into one subject.
struct GradeGroupingSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var second = ""

    var body: some View {
        let grades = container.grades
        let refs = grades.courseRefs(in: container.workspace.snapshot)
        let suggestions = grades.suggestions(in: container.workspace.snapshot)
        VStack(alignment: .leading, spacing: 16) {
            Text("Agrupar materias").font(.title2.weight(.semibold))
            Text("Algunas materias están divididas en dos aulas de SAIA (teoría y laboratorio). Al unirlas, sus puntos se suman en una sola materia.")
                .font(.callout).foregroundStyle(.secondary)
            if !suggestions.isEmpty {
                GroupBox("Sugerencias") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions, id: \.courseKeys) { suggestion in
                            HStack {
                                Text(suggestion.courseKeys.map { name($0, refs) }.joined(separator: " + "))
                                Spacer()
                                Button("Unir") { grades.group(suggestion.courseKeys) }
                                Button("Descartar") { grades.dismiss(suggestion) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
            }
            GroupBox("Materias unidas") {
                VStack(alignment: .leading, spacing: 8) {
                    if grades.settings.groups.isEmpty { Text("Ninguna.").foregroundStyle(.secondary) }
                    ForEach(grades.settings.groups, id: \.self) { group in
                        HStack {
                            Text(group.map { name($0, refs) }.joined(separator: " + "))
                            Spacer()
                            Button("Separar") { group.forEach { grades.ungroup($0) } }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            GroupBox("Unir manualmente") {
                HStack {
                    picker("Materia", selection: $first, refs: refs)
                    Text("+")
                    picker("Con", selection: $second, refs: refs)
                    Button("Unir") {
                        grades.group([first, second])
                        first = ""; second = ""
                    }
                    .disabled(first.isEmpty || second.isEmpty || first == second)
                }
                .padding(4)
            }
            HStack { Spacer(); Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 560)
    }

    private func name(_ key: String, _ refs: [GradeCourseRef]) -> String { refs.first { $0.key == key }?.name ?? key }

    private func picker(_ title: String, selection: Binding<String>, refs: [GradeCourseRef]) -> some View {
        Picker(title, selection: selection) {
            Text("Elegir…").tag("")
            ForEach(refs, id: \.key) { Text($0.name).tag($0.key) }
        }
        .labelsHidden().frame(maxWidth: .infinity)
    }
}
