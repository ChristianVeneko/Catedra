import SwiftUI

/// Create/edit sheet of a study block.
struct StudyBlockSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var block: StudyBlock
    @State private var minutes: Int
    private let isNew: Bool

    init(editor: StudyBlockEditor) {
        _block = State(initialValue: editor.block)
        _minutes = State(initialValue: max(15, Int(editor.block.end.timeIntervalSince(editor.block.start) / 60)))
        isNew = editor.isNew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "Nuevo bloque de estudio" : "Editar bloque de estudio").font(.title3.weight(.semibold)).padding(16)
            Form {
                TextField("Título", text: $block.title)
                DatePicker("Inicio", selection: $block.start)
                Stepper(value: $minutes, in: 15...720, step: 15) { Text("Duración: \(CalendarFormat.hours(Double(minutes) / 60))") }
                Picker("Actividad", selection: activityBinding) {
                    Text("Ninguna").tag(String?.none)
                    ForEach(container.workspace.allActivitiesSorted) { activity in
                        Text("\(activity.name) · \(activity.courseName)").tag(String?.some(activity.id))
                    }
                }
                Toggle("Completado", isOn: $block.done)
                TextField("Notas", text: $block.notes, axis: .vertical).lineLimit(3...6)
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Eliminar", role: .destructive) { container.planner.delete(blockID: block.id); dismiss() }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    block.end = block.start.addingTimeInterval(TimeInterval(minutes * 60))
                    container.planner.save(block)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440)
    }

    private var activityBinding: Binding<String?> {
        Binding {
            block.activityID
        } set: { id in
            block.activityID = id
            guard let activity = container.workspace.activity(id: id) else { block.courseFolder = nil; return }
            block.courseFolder = activity.courseFolderName
            if block.title.trimmingCharacters(in: .whitespaces).isEmpty { block.title = "Estudiar \(activity.name)" }
        }
    }
}
