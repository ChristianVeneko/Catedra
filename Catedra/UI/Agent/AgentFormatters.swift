import SwiftUI

enum AgentFormat {
    static func cost(_ usd: Double) -> String { String(format: "$%.4f", usd) }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 60 ? "\(total / 60) min \(total % 60) s" : "\(total) s"
    }

    static func symbol(forTool name: String) -> String {
        switch name {
        case "Read": "doc.text.magnifyingglass"
        case "Write", "Edit", "MultiEdit", "NotebookEdit": "pencil"
        case "Bash": "terminal"
        case "Glob", "Grep": "magnifyingglass"
        case "Skill": "wand.and.stars"
        default: "wrench"
        }
    }
}

extension AgentRun.Status {
    var label: String {
        switch self {
        case .running: "En curso"
        case .succeeded: "Completado"
        case .failed: "Con errores"
        case .cancelled: "Cancelado"
        }
    }

    var tint: Color {
        switch self {
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .gray
        }
    }

    var symbol: String {
        switch self {
        case .running: "circle.dotted"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "stop.circle.fill"
        }
    }
}

/// Small pulsing indicator shown next to scopes with a running agent.
struct AgentActivityDot: View {
    var body: some View {
        ClaudeMarkView(size: 13, animation: .pulse)
            .help("Hay un agente en ejecución")
    }
}
