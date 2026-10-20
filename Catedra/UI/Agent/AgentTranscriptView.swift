import SwiftUI

struct AgentTranscriptView: View {
    let items: [TranscriptItem]
    let color: Color
    let isRunning: Bool
    var provider: AgentProviderID = .claude

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        row(item).id(item.id)
                    }
                    if isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Trabajando…").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: items.count) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func row(_ item: TranscriptItem) -> some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 60)
                CopyMessageButton(text: text).padding(.top, 8)
                UserBubble(text: text, color: color)
                    .contextMenu { CopyMessageButton.menuItems(text: text) }
            }
        case .assistant(_, let text):
            HStack(alignment: .top, spacing: 10) {
                AgentProviderMark(provider: provider, size: 14).padding(.top, 3)
                MarkdownView(source: text)
                Spacer(minLength: 0)
                CopyMessageButton(text: text)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
            .contextMenu { CopyMessageButton.menuItems(text: text) }
        case .thinking(_, let text):
            DisclosureGroup {
                Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            } label: {
                Label("Razonamiento", systemImage: "brain").font(.callout).foregroundStyle(.secondary)
            }
        case .tool(_, let name, let summary, let result):
            ToolRow(name: name, summary: summary, result: result)
        case .denials(_, let list):
            DenialBanner(denials: list)
        case .error(_, let text):
            Label(text, systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Long prompts collapse to 12 lines with a "Ver más" toggle instead of being cut off.
private struct UserBubble: View {
    static let collapsedLines = 12
    let text: String
    let color: Color
    @State private var expanded = false

    private var isLong: Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).count > Self.collapsedLines || text.count > 900
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(text)
                .textSelection(.enabled)
                .lineLimit(expanded ? nil : Self.collapsedLines)
            if isLong {
                Button(expanded ? "Ver menos" : "Ver más") { withAnimation(.snappy) { expanded.toggle() } }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Copies the whole message in one go; per-block text selection cannot span bullets or tables.
/// The default copy carries HTML (Word, Pages, Notion keep the format) plus the Markdown source as plain text.
private struct CopyMessageButton: View {
    let text: String
    @State private var copied = false

    static func copyFormatted(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MarkdownExport.html(text), forType: .html)
        pasteboard.setString(text, forType: .string)
    }

    static func copyString(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @ViewBuilder
    static func menuItems(text: String) -> some View {
        Button("Copiar mensaje", systemImage: "doc.on.doc") { copyFormatted(text) }
        Button("Copiar como Markdown", systemImage: "number") { copyString(text) }
        Button("Copiar como texto", systemImage: "text.alignleft") { copyString(MarkdownExport.plainText(text)) }
    }

    var body: some View {
        Button {
            Self.copyFormatted(text)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copiado" : "Copiar mensaje completo")
        .accessibilityLabel("Copiar mensaje completo")
    }
}

private struct ToolRow: View {
    let name: String
    let summary: String
    let result: TranscriptItem.ToolOutcome?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: AgentFormat.symbol(forTool: name)).frame(width: 18).foregroundStyle(.secondary)
                    Text(name).font(.callout.weight(.semibold))
                    Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let result {
                        Image(systemName: result.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(result.isError ? .red : .green)
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !summary.isEmpty { Text(summary).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    if let result, !result.preview.isEmpty {
                        Divider()
                        Text(result.preview).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(result.isError ? .red : .secondary).textSelection(.enabled)
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct DenialBanner: View {
    let denials: [PermissionDenial]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(denials.enumerated()), id: \.offset) { _, denial in
                Label("El agente no pudo usar: \(denial.toolName)\(denial.summary.isEmpty ? "" : " \(denial.summary)")",
                      systemImage: "lock.fill")
                    .lineLimit(2).truncationMode(.middle)
            }
            Text("Cambie el modo de permisos y vuelva a enviar el mensaje para permitir estas acciones.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.orange)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
