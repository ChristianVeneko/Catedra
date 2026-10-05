import SwiftUI

/// "Revisión previa": checklist produced by the `review-draft` recipe, plus the button that runs it.
struct DraftReviewSection: View {
    @Environment(AppContainer.self) private var container
    let model: ActivityDetailModel
    let color: Color

    private var scope: AgentScope { .activity(model.activity) }
    private var isRunning: Bool { container.agents.isRunning(scopeID: scope.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Revisión previa")
                Spacer()
                runButton
            }
            VStack(alignment: .leading, spacing: 12) {
                content
                if let error = container.agents.startErrors[scope.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private var runButton: some View {
        let hasReview: Bool = { if case .loaded = model.review { return true } else { return false } }()
        return Button(action: run) {
            Label(hasReview ? "Volver a revisar" : "Revisar entrega", systemImage: "checklist")
        }
        .disabled(!model.canReview || isRunning)
        .help(model.canReview ? "Un agente compara la entrega con el enunciado y las Normas UFT. No modifica tus archivos."
                              : "Agrega archivos a «Entrega» para poder revisarlos.")
    }

    @ViewBuilder
    private var content: some View {
        if isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Revisando la entrega…")
                Spacer()
                Button("Ver agente") { container.navigation.activityTab = .agent }.buttonStyle(.link)
            }
        }
        switch model.review {
        case .loaded(let review):
            checklist(review)
        case .invalid(let reason):
            Label("No se pudo leer la última revisión. \(reason) Vuelva a ejecutarla.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .missing:
            if !model.canReview {
                Label("Aún no hay archivos en «Entrega». Agréguelos para poder revisarlos antes de enviar.", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else if !isRunning {
                Text("Un agente comparará su entrega con el enunciado (y la rúbrica, si existe) y revisará el formato de las Normas UFT.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func checklist(_ review: DraftReview) -> some View {
        let counts = review.counts
        HStack(spacing: 12) {
            countChip(counts.cumple, "Cumple", .cumple)
            countChip(counts.parcial, "Parcial", .parcial)
            countChip(counts.falta, "Falta", .falta)
            if counts.unknown > 0 { countChip(counts.unknown, "Sin clasificar", .unknown) }
            Spacer()
            if let date = review.generatedAt {
                Text("Revisado: \(Formatters.due(date))").font(.caption).foregroundStyle(.secondary)
            }
        }
        if !review.summary.isEmpty { Text(review.summary).textSelection(.enabled) }
        if review.requirements.isEmpty {
            Text("La revisión no devolvió requisitos.").foregroundStyle(.secondary)
        } else {
            Divider()
            ForEach(review.requirements) { RequirementRow(requirement: $0) }
        }
        Text("Sugerencias de un agente: revíselas usted. No sustituyen la evaluación del docente.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func countChip(_ count: Int, _ title: String, _ status: RequirementStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName).foregroundStyle(status.color)
            Text("\(count) \(title)").font(.callout.weight(.medium))
        }
    }

    private func run() {
        let recipe = RecipeCatalog.recipe(id: "review-draft")
        guard let recipe else { return }
        let prompt = RecipeCatalog.render(recipe, scope: scope, activities: [], formatDate: Formatters.due)
        let options = container.settings.defaultOptions(for: container.settings.agentProvider)
        container.agents.start(scope: scope, prompt: prompt, recipe: recipe, options: options)
    }
}

private struct RequirementRow: View {
    let requirement: ReviewRequirement
    @State private var expanded = false

    private var hasDetail: Bool { !requirement.evidence.isEmpty || requirement.suggestion != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { if hasDetail { withAnimation(.snappy) { expanded.toggle() } } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: requirement.status.symbolName).foregroundStyle(requirement.status.color)
                    Text(requirement.requirement).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(requirement.source.label).font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                    if hasDetail {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !requirement.evidence.isEmpty {
                        Text("Evidencia: \(requirement.evidence)").font(.callout).foregroundStyle(.secondary)
                    }
                    if let suggestion = requirement.suggestion {
                        Text("Sugerencia: \(suggestion)").font(.callout)
                    }
                }
                .textSelection(.enabled).padding(.leading, 24)
            }
        }
    }
}

extension RequirementStatus {
    var symbolName: String {
        switch self {
        case .cumple: "checkmark.circle.fill"
        case .parcial: "circle.lefthalf.filled"
        case .falta: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .cumple: .green
        case .parcial: .orange
        case .falta: .red
        case .unknown: .secondary
        }
    }
}

extension RequirementSource {
    var label: String {
        switch self {
        case .enunciado: "Enunciado"
        case .rubrica: "Rúbrica"
        case .normasUFT: "Normas UFT"
        case .unknown: "Otro"
        }
    }
}
