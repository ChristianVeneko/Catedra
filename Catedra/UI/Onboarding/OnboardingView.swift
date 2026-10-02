import SwiftUI
import AppKit

/// First-run setup wizard (also re-runnable from Settings and the app menu).
struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = container.onboarding
        VStack(spacing: 0) {
            ProgressDots(current: model.step, onSelect: { model.go(to: $0) })
                .padding(.top, 20).padding(.bottom, 8)
            ScrollView {
                stepView(model)
                    .padding(.horizontal, 36).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(model.step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer(model).padding(.horizontal, 28).padding(.vertical, 14)
        }
        .frame(width: 760, height: 640)
        .animation(.easeInOut(duration: 0.22), value: model.step)
        .onAppear { model.begin() }
    }

    @ViewBuilder
    private func stepView(_ model: OnboardingModel) -> some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .folder: FolderStep(model: model)
        case .credentials: CredentialsStep(model: model)
        case .agent: AgentStep(model: model)
        case .dependencies: DependenciesStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    private func footer(_ model: OnboardingModel) -> some View {
        HStack {
            if !model.isFirst {
                Button("Atrás") { model.back() }.keyboardShortcut(.cancelAction)
            }
            Spacer()
            if model.isLast {
                Button {
                    Task { if await model.finish() { dismiss() } }
                } label: {
                    if model.isFinishing { ProgressView().controlSize(.small) } else { Text(model.syncNow && model.canSyncNow ? "Finalizar y sincronizar" : "Finalizar") }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                .disabled(model.isFinishing)
            } else {
                Button(nextTitle(model)) { model.next() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdvance)
            }
        }
    }

    private func nextTitle(_ model: OnboardingModel) -> String {
        switch model.step {
        case .welcome: "Comenzar"
        case .credentials: model.username.isEmpty && model.password.isEmpty ? "Omitir por ahora" : "Continuar"
        default: "Continuar"
        }
    }
}

// MARK: - Shared pieces

private struct ProgressDots: View {
    let current: OnboardingModel.Step
    let onSelect: (OnboardingModel.Step) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step <= current ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: step == current ? 26 : 8, height: 8)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(step) }
                        .accessibilityLabel(step.title)
                }
            }
            Text("Paso \(current.rawValue + 1) de \(OnboardingModel.Step.allCases.count) · \(current.title)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .animation(.spring(duration: 0.3), value: current)
    }
}

struct StepHeader: View {
    let symbol: String
    let title: String
    var tint: Color = .accentColor
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 14)
    }
}

private struct InfoCard<Content: View>: View {
    var tint: Color? = nil
    var selected = false
    @ViewBuilder var content: Content

    var body: some View {
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading).card(tint: tint, selected: selected)
    }
}

private struct Note: View {
    let text: String
    var symbol = "info.circle"
    var tint: Color = .secondary

    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
            .font(.caption).foregroundStyle(tint)
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(symbol: "graduationcap.fill", title: "Bienvenido a Cátedra",
                       subtitle: "Un tablero local para tus materias del SAIA: qué vence, qué entregar y dónde trabajar.")
            feature("calendar.badge.clock", .orange, "Qué vence y cuándo",
                    "Sincroniza tus actividades y las ordena por fecha límite, con cuenta regresiva y estado.")
            feature("doc.text.magnifyingglass", .blue, "Enunciados y contenidos",
                    "Lee enunciados, imágenes, páginas y foros descargados en tu equipo, sin abrir el navegador.")
            feature("folder.badge.plus", .green, "Tu trabajo, en su sitio",
                    "Guarda entregas, borradores y apuntes por actividad. Nada se mueve ni se sube solo.")
            feature("sparkles", .purple, "Agentes de IA opcionales",
                    "Usa Claude Code, Antigravity u OpenCode sobre una materia o actividad. Todo resultado es un borrador para tu revisión.")
            Note(text: "Este asistente tarda unos minutos y puede volver a ejecutarse desde Ajustes.")
                .padding(.top, 4)
        }
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        InfoCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 2. Folder

private struct FolderStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(symbol: "folder.fill", title: "Carpeta de datos", tint: .blue,
                       subtitle: "Elige la carpeta donde se guardarán las materias, o crea una nueva.")
            InfoCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Ruta", text: Binding(get: { model.folderPath }, set: { model.setFolder($0) }))
                            .textFieldStyle(.roundedBorder)
                        Button("Elegir o crear…") { choose() }
                    }
                    status
                }
            }
            if model.offersStarterFiles {
                InfoCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Crear instrucciones de inicio para el agente", isOn: $model.createStarterFiles)
                            .toggleStyle(.checkbox).font(.headline)
                        Text("Se crean «AGENTS.md» (estructura de carpetas y reglas) y «CLAUDE.md» (que lo importa). Nunca se sobrescribe un archivo existente.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let inspection = model.inspection {
            if !inspection.isWritable {
                Label("No se puede escribir en esta carpeta. Elija otra.", systemImage: "lock.fill").foregroundStyle(.red)
            } else if let count = inspection.existingActivityCount {
                Label("Se encontró un espacio existente con \(count) actividades", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if !inspection.exists {
                Label("La carpeta se creará al finalizar.", systemImage: "plus.circle").foregroundStyle(.secondary)
            } else {
                Label(inspection.isEmpty ? "Carpeta vacía lista para usar." : "Carpeta sin sincronizar todavía; se añadirán las materias.",
                      systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true // shows the "Nueva carpeta" button
        panel.prompt = "Elegir"
        panel.message = "Elija la carpeta de datos o cree una nueva con «Nueva carpeta»."
        let current = URL(fileURLWithPath: model.folderPath, isDirectory: true)
        panel.directoryURL = FileManager.default.fileExists(atPath: current.path) ? current : current.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { model.setFolder(url.path) }
    }
}

// MARK: - 3. Credentials

private struct CredentialsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(symbol: "key.fill", title: "Credenciales del SAIA", tint: .orange,
                       subtitle: "Se guardan solo en el llavero de macOS y se usan para sincronizar. Puedes omitir este paso.")
            InfoCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Usuario", text: $model.username).textFieldStyle(.roundedBorder)
                    SecureField("Contraseña", text: $model.password,
                                prompt: Text(model.hasStoredCredentials ? "Ya hay una contraseña guardada en el llavero" : "Contraseña"))
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 10) {
                        Button("Probar conexión") { model.testConnection() }.disabled(!model.canTestConnection)
                        result
                    }
                    if model.password.isEmpty, !model.username.isEmpty, model.hasStoredCredentials {
                        Note(text: "Escriba la contraseña solo si desea cambiarla o probar la conexión.")
                    }
                }
            }
            .onChange(of: model.username) { _, _ in model.credentialsChanged() }
            .onChange(of: model.password) { _, _ in model.credentialsChanged() }
            Note(text: "La prueba envía el usuario y la contraseña a saia.uft.edu.ve (token de la app móvil). El token no se guarda ni se registra.",
                 symbol: "lock.shield")
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.authState {
        case .idle: EmptyView()
        case .testing: ProgressView().controlSize(.small)
        case .finished(let outcome):
            Label(outcome.message, systemImage: outcome.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.callout).foregroundStyle(outcome.isSuccess ? .green : .red).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 4. Agent

private extension AgentProviderID {
    var onboardingSummary: String {
        switch self {
        case .claude: "El agente de Anthropic. Funciona con una suscripción de Claude o una clave de API."
        case .antigravity: "El agente de Google, mediante la CLI «agy». Elige entre los modelos que ofrezca su cuenta."
        case .opencode: "Agente de código abierto compatible con muchos proveedores de modelos mediante clave de API."
        }
    }
}

private struct AgentStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(symbol: "sparkles", title: "Agente", tint: .purple,
                       subtitle: "Elige el agente que usarán las conversaciones nuevas. Puedes cambiarlo en Ajustes.")
            ForEach(AgentProviderID.allCases) { provider in
                Button { model.provider = provider } label: {
                    InfoCard(selected: model.provider == provider) {
                        HStack(alignment: .top, spacing: 14) {
                            AgentProviderMark(provider: provider, size: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(provider.displayName).font(.headline)
                                    installBadge(provider)
                                }
                                Text(provider.onboardingSummary).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: model.provider == provider ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(model.provider == provider ? Color.accentColor : .secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.provider == provider ? .isSelected : [])
            }
            if let warning = model.provider.tosWarning {
                Note(text: warning, symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            Note(text: "El estado de instalación viene de las comprobaciones del paso siguiente; allí verás cómo instalar lo que falte.")
        }
    }

    @ViewBuilder
    private func installBadge(_ provider: AgentProviderID) -> some View {
        if let check = model.check(for: provider) {
            switch check.status {
            case .checking: ProgressView().controlSize(.mini)
            case .ok: Badge(text: check.version.map { "Instalado · v\($0)" } ?? "Instalado", tint: .green)
            default: Badge(text: "No instalado", tint: .orange)
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 2).background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - 5. Dependencies

private struct DependenciesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(symbol: "checklist", title: "Dependencias", tint: .teal,
                       subtitle: "Lo necesario para sincronizar y usar el agente. Puedes terminar aunque falte algo; la app te lo recordará.")
            ForEach(model.checks) { check in
                DependencyRow(check: check, model: model)
            }
            HStack {
                Button { model.recheck() } label: { Label("Volver a comprobar", systemImage: "arrow.clockwise") }
                    .disabled(model.isChecking)
                if model.isChecking { ProgressView().controlSize(.small) }
            }
            if !model.pipOutput.isEmpty {
                ScrollView {
                    Text(model.pipOutput.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                .frame(maxHeight: 130)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct DependencyRow: View {
    let check: DependencyCheck
    @Bindable var model: OnboardingModel

    var body: some View {
        InfoCard {
            HStack(alignment: .top, spacing: 12) {
                icon.frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(check.name).font(.headline)
                        Badge(text: statusText, tint: tint)
                        if check.requirement == .optional, check.status != .ok { Badge(text: "Opcional", tint: .secondary) }
                    }
                    if let detail = detailText { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle) }
                    if needsInstallHelp, let command = check.installCommand { installHelp(command) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var needsInstallHelp: Bool {
        switch check.status {
        case .missing, .outdated: true
        default: false
        }
    }

    private var tint: Color {
        switch check.status {
        case .ok: .green
        case .checking: .secondary
        case .missing: check.requirement == .required ? .red : .secondary
        case .outdated: .orange
        }
    }

    private var statusText: String {
        switch check.status {
        case .checking: "Comprobando…"
        case .ok: check.version.map { "OK · v\($0)" } ?? "OK"
        case .missing: "Falta"
        case .outdated(let found, let minimum): "Versión \(found) (se requiere ≥ \(minimum))"
        }
    }

    private var detailText: String? {
        if let detail = check.detail, check.status != .checking { return detail }
        if check.status == .checking { return nil }
        return check.note
    }

    @ViewBuilder
    private var icon: some View {
        switch check.status {
        case .checking: ProgressView().controlSize(.small)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
        case .missing:
            Image(systemName: check.requirement == .required ? "xmark.octagon.fill" : "minus.circle")
                .foregroundStyle(check.requirement == .required ? .red : .secondary).font(.title3)
        case .outdated: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
        }
    }

    private func installHelp(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                if check.installIsCommand { Button("Copiar") { copyToPasteboard(command) }.controlSize(.small) }
                if check.id == .requests, check.status != .checking {
                    Button(model.isInstallingRequests ? "Instalando…" : "Instalar") { model.installRequests() }
                        .controlSize(.small).disabled(model.isInstallingRequests || model.pythonPath.isEmpty)
                        .help("Ejecuta «python3 -m pip install --user requests»")
                }
            }
            if check.id == .requests, !model.pythonPath.isEmpty {
                Note(text: "«Instalar» solo se ejecuta si lo pulsas.")
            }
        }
    }
}

// MARK: - 6. Done

private struct DoneStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(symbol: "checkmark.seal.fill", title: "Todo listo", tint: .green,
                       subtitle: "Esta es la configuración que se guardará al finalizar.")
            InfoCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.summary.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                            Text(row.value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            if case .blocked = model.readiness {
                Note(text: "Faltan dependencias obligatorias. Puedes finalizar, pero la app mostrará un aviso hasta que las instales.",
                     symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            InfoCard {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Sincronizar ahora", isOn: $model.syncNow).toggleStyle(.checkbox).font(.headline)
                        .disabled(!model.canSyncNow)
                    Text(model.canSyncNow
                         ? "Copia el script de sincronización a la carpeta de datos y descarga tus materias."
                         : "Requiere credenciales y las dependencias obligatorias. Podrás sincronizar luego con ⌘R.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error = model.finishError {
                Note(text: error, symbol: "xmark.octagon.fill", tint: .red)
            }
        }
    }
}
