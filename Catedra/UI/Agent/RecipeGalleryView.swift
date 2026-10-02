import SwiftUI

struct RecipeGalleryView: View {
    let scope: AgentScope
    let recipes: [Recipe]
    let color: Color
    let select: (Recipe) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(color)
                    Text("Agente").font(.largeTitle.weight(.bold))
                    Text(scope.kind == .course
                         ? "Trabaja con todo el contenido de «\(scope.title)». Elija una receta o escriba su propia instrucción abajo."
                         : "Trabaja dentro de esta actividad. Elija una receta o escriba su propia instrucción abajo.")
                        .foregroundStyle(.secondary)
                }
                if !recipes.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(recipes) { recipe in
                            Button { select(recipe) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: recipe.symbol).font(.title2).foregroundStyle(color)
                                    Text(recipe.title).font(.headline).multilineTextAlignment(.leading)
                                    Text(recipe.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                                .card(tint: color)
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Label("Todo lo que el agente genera es un borrador: revíselo y entréguelo usted mismo.", systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Editable prompt shown after choosing a recipe, before running it.
struct RecipePromptEditor: View {
    let recipe: Recipe
    @Binding var text: String
    let color: Color
    let run: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(recipe.title, systemImage: recipe.symbol).font(.title2.weight(.semibold))
            Text("Revise o edite la instrucción antes de ejecutarla.").foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(minHeight: 260)
            HStack {
                Button("Cancelar", action: cancel)
                Spacer()
                Button(action: run) { Label("Ejecutar", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(color)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}
