import SwiftUI

/// Dismissible card in "Hoy" with the weekly summary (agent-written or the plain local digest).
struct WeeklySummaryCard: View {
    @Environment(AppContainer.self) private var container
    let now: Date

    var body: some View {
        if let card = container.weekly.card(now: now) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Resumen de la semana", systemImage: "text.badge.checkmark").font(.headline)
                    if !card.usedAgent {
                        Text("Resumen local").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Button { container.weekly.dismiss(now: now) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("Descartar").accessibilityLabel("Descartar resumen")
                }
                MarkdownView(source: card.text, skipFirstHeading: true, baseURL: nil)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }
}
