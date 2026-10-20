import SwiftUI

/// Black island that grows out of the notch: section and progress, the current sentence with the spoken words lit up
/// (karaoke style), and the next sentence dimmed. Controls appear on hover.
struct TeleprompterIslandView: View {
    let model: TeleprompterModel
    /// Height of the notch (0 on screens without one); content starts below it.
    let notchHeight: CGFloat
    /// Reports the island's height so the panel can match it and leave the rest of the screen clickable.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var appeared = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(notchHeight, 6))
            if let script = model.script {
                content(script)
                    .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(NotchIslandShape(flare: 10, radius: 26).fill(.black))
        .overlay(alignment: .bottomTrailing) { if hovering { controls.padding(10).transition(.opacity) } }
        .scaleEffect(x: appeared ? 1 : 0.4, y: appeared ? 1 : 0.15, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { appeared = true } }
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .environment(\.colorScheme, .dark)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
    }

    @ViewBuilder
    private func content(_ script: Script) -> some View {
        let current = model.currentSentence
        VStack(alignment: .leading, spacing: 8) {
            header(script)
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { model.dismissNotice() }
            }
            // Fixed-height, clipped box: the incoming sentence pushes the old one out without the two overlapping
            // the rows around it.
            ZStack(alignment: .topLeading) {
                sentence(script, index: current)
                    .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id(current)
                    .transition(.push(from: .bottom))
            }
            .frame(height: sentenceHeight, alignment: .topLeading)
            .clipped()
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: current)
            Text(current + 1 < script.sentences.count ? script.sentences[current + 1].text : " ")
                .font(.system(size: model.fontSize * 0.62, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two lines of the current sentence at the chosen size.
    private var sentenceHeight: CGFloat { (model.fontSize * 1.28 * 2).rounded(.up) }

    private func header(_ script: Script) -> some View {
        let section = script.sections.indices.contains(model.currentSection) ? script.sections[model.currentSection].title : ""
        return HStack(spacing: 8) {
            statusIcon
            Text(section.isEmpty ? script.title : section)
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Spacer(minLength: 8)
            Capsule().fill(.white.opacity(0.18))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.85)).frame(width: geo.size.width * model.progress)
                    }
                }
                .frame(width: 70, height: 4)
                .animation(.easeOut(duration: 0.25), value: model.progress)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.state {
        case .paused:
            Image(systemName: "pause.fill").foregroundStyle(.yellow)
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        default:
            if model.activeMode == .voice {
                Image(systemName: "waveform").foregroundStyle(.green).symbolEffect(.variableColor.iterative, isActive: true)
            } else {
                Image(systemName: "metronome.fill").foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// Spoken words in white, the rest dimmed; cues as small orange labels.
    private func sentence(_ script: Script, index: Int) -> Text {
        guard script.sentences.indices.contains(index) else { return Text("") }
        var result = Text("")
        for token in script.sentences[index].tokens {
            switch token {
            case .word(let word):
                let spoken = word < model.position
                let next = word == model.position
                result = result + Text(script.words[word].text + " ")
                    .foregroundStyle(spoken ? .white : .white.opacity(next ? 0.75 : 0.42))
            case .cue(let cue):
                result = result + Text("[\(cue)] ")
                    .font(.system(size: model.fontSize * 0.6, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
        return result
    }

    private var controls: some View {
        HStack(spacing: 4) {
            button("backward.fill", "Frase anterior (⌃⌥←)") { model.previousSentence() }
            button(model.state == .running ? "pause.fill" : "play.fill", "Pausar o seguir (⌃⌥Espacio)") { model.togglePause() }
            button("forward.fill", "Frase siguiente (⌃⌥→)") { model.nextSentence() }
            button("xmark", "Cerrar guion (⌃⌥Esc)") { model.close() }
        }
        .padding(4)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Island outline: flush with the top edge, small outward flares at the top corners (so it reads as part of the
/// notch / menu bar), and rounded bottom corners.
struct NotchIslandShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, rect.height / 2, (rect.width - 2 * flare) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + flare, y: rect.minY + flare), control: CGPoint(x: rect.minX + flare, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + flare, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + flare + r, y: rect.maxY), control: CGPoint(x: rect.minX + flare, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - flare - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - flare, y: rect.maxY - r), control: CGPoint(x: rect.maxX - flare, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - flare, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
