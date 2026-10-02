import SwiftUI
import AppKit

/// Four-point sparkle with concave sides (the Gemini-style star used for Antigravity).
struct AntigravityMark: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        // Each side is a quadratic curve pulled toward the center, which makes the sides concave.
        let pull: CGFloat = 0.14 * r
        var path = Path()
        let top = CGPoint(x: c.x, y: c.y - r), right = CGPoint(x: c.x + r, y: c.y)
        let bottom = CGPoint(x: c.x, y: c.y + r), left = CGPoint(x: c.x - r, y: c.y)
        path.move(to: top)
        path.addQuadCurve(to: right, control: CGPoint(x: c.x + pull, y: c.y - pull))
        path.addQuadCurve(to: bottom, control: CGPoint(x: c.x + pull, y: c.y + pull))
        path.addQuadCurve(to: left, control: CGPoint(x: c.x - pull, y: c.y + pull))
        path.addQuadCurve(to: top, control: CGPoint(x: c.x - pull, y: c.y - pull))
        path.closeSubpath()
        return path
    }
}

extension LinearGradient {
    /// Blue → purple → coral, as in the Gemini sparkle.
    static let antigravity = LinearGradient(
        colors: [Color(red: 0x42 / 255, green: 0x85 / 255, blue: 0xF4 / 255),
                 Color(red: 0x9B / 255, green: 0x72 / 255, blue: 0xCB / 255),
                 Color(red: 0xD9 / 255, green: 0x65 / 255, blue: 0x70 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Monochrome OpenCode mark: a rounded square outline with an inner block (a terminal cursor).
struct OpenCodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let stroke = side * 0.14
        var path = Path()
        // Outline as an even-odd ring.
        path.addRoundedRect(in: box, cornerSize: CGSize(width: side * 0.2, height: side * 0.2))
        path.addRoundedRect(in: box.insetBy(dx: stroke, dy: stroke),
                            cornerSize: CGSize(width: side * 0.08, height: side * 0.08))
        // Inner block, lower half.
        let inner = box.insetBy(dx: side * 0.3, dy: side * 0.3)
        path.addRect(CGRect(x: inner.minX, y: inner.midY, width: inner.width, height: inner.height / 2))
        return path
    }
}

enum AgentMarkAnimation { case none, spin, pulse }

/// The mark of an agent provider at a given point size, optionally animated.
struct AgentProviderMark: View {
    let provider: AgentProviderID
    var size: CGFloat = 16
    var animation: AgentMarkAnimation = .none

    init(provider: AgentProviderID, size: CGFloat = 16, animation: AgentMarkAnimation = .none) {
        self.provider = provider
        self.size = size
        self.animation = animation
    }

    init(provider: AgentProviderID, size: CGFloat = 16, animated: Bool) {
        self.init(provider: provider, size: size, animation: animated ? .pulse : .none)
    }

    var body: some View {
        switch animation {
        case .none:
            mark
        case .spin:
            TimelineView(.animation) { context in
                mark.rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360))
            }
        case .pulse:
            TimelineView(.animation) { context in
                let phase = sin(context.date.timeIntervalSinceReferenceDate * 2.4)
                mark.scaleEffect(1 + 0.12 * phase).opacity(0.8 + 0.2 * phase)
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        Group {
            switch provider {
            case .claude:
                ClaudeMark().fill(Color.claudeTerracotta)
            case .antigravity:
                AntigravityMark().fill(LinearGradient.antigravity)
            case .opencode:
                OpenCodeMark().fill(Color.primary, style: FillStyle(eoFill: true))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Overlapping marks for several providers (badge with agents of different providers running).
struct AgentProviderMarkStack: View {
    let providers: [AgentProviderID]
    var size: CGFloat = 16
    var animation: AgentMarkAnimation = .none

    var body: some View {
        if providers.count <= 1 {
            AgentProviderMark(provider: providers.first ?? .claude, size: size, animation: animation)
        } else {
            HStack(spacing: -size * 0.3) {
                ForEach(providers) { provider in
                    AgentProviderMark(provider: provider, size: size * 0.85, animation: animation)
                        .padding(size * 0.05)
                        .background(Circle().fill(.background))
                }
            }
        }
    }
}

/// Drop-in for `Label(title, systemImage:)` where the icon represents an agent provider.
struct AgentProviderLabel: View {
    let title: String
    let provider: AgentProviderID
    var size: CGFloat = 14
    var animation: AgentMarkAnimation = .none

    init(_ title: String, provider: AgentProviderID, size: CGFloat = 14, animation: AgentMarkAnimation = .none) {
        self.title = title
        self.provider = provider
        self.size = size
        self.animation = animation
    }

    var body: some View {
        Label { Text(title) } icon: { AgentProviderMark(provider: provider, size: size, animation: animation) }
    }
}

@MainActor
enum AgentProviderMarkImage {
    /// Rasterized mark for places that only accept images (segmented pickers, menus). The monochrome OpenCode mark
    /// is a template image so the system tints it for light and dark appearances.
    static func image(_ provider: AgentProviderID, size: CGFloat) -> Image {
        let renderer = ImageRenderer(content: AgentProviderMark(provider: provider, size: size))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let nsImage = renderer.nsImage else { return Image(systemName: "circle") }
        nsImage.isTemplate = provider == .opencode
        return Image(nsImage: nsImage)
    }
}
