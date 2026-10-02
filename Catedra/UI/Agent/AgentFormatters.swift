import SwiftUI

enum AgentFormat {
    static func cost(_ usd: Double) -> String { String(format: "$%.4f", usd) }

    static func tokens(input: Int, output: Int) -> String {
        func short(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }
        return "\(short(input)) ↓ · \(short(output)) ↑"
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 60 ? "\(total / 60) min \(total % 60) s" : "\(total) s"
    }

    /// Tool names of Antigravity (`view_file`, `run_command`, …) and OpenCode (`read`, `bash`, …).
    private static func symbolForOtherProviders(_ name: String) -> String {
        let tool = name.lowercased()
        if tool.hasPrefix("browser_") { return "globe" }
        switch tool {
        case "view_file", "view_file_outline", "view_code_item", "list_dir", "read", "list": return "doc.text.magnifyingglass"
        case "grep_search", "find_by_name", "codebase_search", "grep", "glob", "search_web", "read_url_content", "webfetch", "websearch":
            return "magnifyingglass"
        case "write_to_file", "replace_file_content", "multi_replace_file_content", "edit", "write", "patch", "apply_patch": return "pencil"
        case "run_command", "bash", "command_status", "send_command_input": return "terminal"
        case "task", "todowrite", "todoread": return "checklist"
        default: return "wrench"
        }
    }

    static func symbol(forTool name: String) -> String {
        switch name {
        case "Read": "doc.text.magnifyingglass"
        case "Write", "Edit", "MultiEdit", "NotebookEdit": "pencil"
        case "Bash": "terminal"
        case "Glob", "Grep": "magnifyingglass"
        case "Skill": "wand.and.stars"
        default: symbolForOtherProviders(name)
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
    let providers: [AgentProviderID]

    var body: some View {
        AgentProviderMarkStack(providers: providers, size: 13, animation: .pulse)
            .help("Hay un agente en ejecución")
    }
}
