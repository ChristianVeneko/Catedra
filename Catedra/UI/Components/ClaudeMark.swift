import SwiftUI
import AppKit

/// Vector approximation of the Claude starburst: 12 tapered rays of uneven length with rounded tips.
struct ClaudeMark: Shape {
    /// Relative ray lengths (1 = full radius), clockwise from the top.
    private static let lengths: [CGFloat] = [1.0, 0.74, 0.92, 0.68, 0.98, 0.78, 0.94, 0.7, 0.9, 0.8, 1.0, 0.72]
    private static let angleJitter: [CGFloat] = [0, 2, -1.5, 1, -2, 1.5, 0, -1, 2, -1.5, 1, -2]

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let count = Self.lengths.count
        var path = Path()
        for i in 0..<count {
            let degrees = CGFloat(i) * 360 / CGFloat(count) + Self.angleJitter[i] - 90
            let angle = degrees * .pi / 180
            let length = radius * Self.lengths[i]
            let tipHalf = radius * 0.09      // half width at the (rounded) tip
            let baseHalf = radius * 0.028      // half width near the center
            let tipCenter = length - tipHalf
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let normal = CGPoint(x: -direction.y, y: direction.x)
            func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
                CGPoint(x: center.x + direction.x * along + normal.x * across,
                        y: center.y + direction.y * along + normal.y * across)
            }
            path.move(to: point(0, -baseHalf))
            path.addLine(to: point(tipCenter, -tipHalf))
            path.addArc(center: point(tipCenter, 0), radius: tipHalf,
                        startAngle: .radians(Double(angle) - .pi / 2), endAngle: .radians(Double(angle) + .pi / 2),
                        clockwise: false)
            path.addLine(to: point(0, baseHalf))
            path.closeSubpath()
        }
        return path
    }
}

/// Fixed brand terracotta; it deliberately ignores the course accent color.
extension Color {
    static let claudeTerracotta = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
}

enum ClaudeMarkAnimation { case none, spin, pulse }

/// The Claude mark at a given point size, optionally animated.
struct ClaudeMarkView: View {
    var size: CGFloat = 16
    var animation: ClaudeMarkAnimation = .none

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

    private var mark: some View {
        ClaudeMark()
            .fill(Color.claudeTerracotta)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Drop-in for `Label(title, systemImage:)` where the icon represents Claude.
struct ClaudeLabel: View {
    let title: String
    var size: CGFloat = 14
    var animation: ClaudeMarkAnimation = .none

    init(_ title: String, size: CGFloat = 14, animation: ClaudeMarkAnimation = .none) {
        self.title = title
        self.size = size
        self.animation = animation
    }

    var body: some View {
        Label { Text(title) } icon: { ClaudeMarkView(size: size, animation: animation) }
    }
}

@MainActor
enum ClaudeMarkImage {
    /// Rasterized mark for places that only accept images (segmented pickers, menus).
    static func image(size: CGFloat) -> Image {
        let renderer = ImageRenderer(content: ClaudeMarkView(size: size))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let nsImage = renderer.nsImage else { return Image(systemName: "circle") }
        nsImage.isTemplate = false
        return Image(nsImage: nsImage)
    }
}
