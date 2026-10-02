import SwiftUI

/// Non-modal toast for the result of a background sync.
struct SyncBannerView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let banner = container.sync.banner {
                HStack(spacing: 10) {
                    switch banner {
                    case .summary(let text):
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Sincronizado · \(text)")
                    case .failure(let text, let needsSettings):
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(text).lineLimit(2)
                        Button("Ver detalles") { container.sync.isPresented = true }.controlSize(.small)
                        if needsSettings { Button("Ajustes") { openSettings() }.controlSize(.small) }
                    }
                    Button { container.sync.dismissBanner() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).controlSize(.small)
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: container.sync.banner)
    }
}
