import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = container.settings
        Form {
            Section("Espacio de trabajo") {
                HStack {
                    TextField("Ruta", text: $settings.workspacePath)
                    Button("Elegir…") { chooseFolder() }
                }
                Text("Carpeta que contiene las materias y la carpeta «_sistema».").font(.caption).foregroundStyle(.secondary)
            }
            Section("Barra de menús") {
                Toggle("Mostrar en la barra de menús", isOn: $settings.menuBarVisible)
                Toggle("Mostrar la cuenta regresiva", isOn: $settings.menuBarShowsCountdown)
                    .disabled(!settings.menuBarVisible)
                Text("Ícono con el tiempo que falta para la próxima entrega: naranja con menos de 24 h y rojo con menos de 3 h.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sincronización") {
                Picker("Al abrir la app", selection: $settings.launchSyncMode) {
                    ForEach(LaunchSyncMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("No repetir si la última fue hace menos de \(settings.launchSyncMinIntervalMinutes) min",
                        value: $settings.launchSyncMinIntervalMinutes, in: 0...720, step: 5)
                    .disabled(settings.launchSyncMode == .off)
                Text("Se ejecuta en segundo plano con prioridad baja, sin abrir ventanas, y solo si ya completó el asistente y guardó sus credenciales.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RemindersSection(settings: settings)
            Section("Asistente de configuración") {
                Button("Volver a ejecutar el asistente") { openWindow(id: "onboarding") }
                Text("Guía paso a paso: carpeta de datos, credenciales del SAIA, agente y dependencias.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Python") {
                HStack {
                    TextField("Intérprete", text: $settings.pythonPath, prompt: Text("/opt/homebrew/bin/python3"))
                    Button("Detectar") { Task { await settings.detectPython() } }
                }
                if let status = settings.pythonStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                Text("Debe tener instalado el módulo «requests».").font(.caption).foregroundStyle(.secondary)
            }
            Section("Agente") {
                Picker("Proveedor", selection: $settings.agentProvider) {
                    ForEach(AgentProviderID.allCases) { provider in
                        Label { Text(provider.displayName) } icon: { AgentProviderMarkImage.image(provider, size: 14) }.tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                Text("Proveedor de las conversaciones nuevas. Cada conversación guardada sigue usando el suyo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(AgentProviderID.allCases) { provider in
                ProviderSettingsSection(provider: provider, settings: settings)
            }
            Section("Cuenta de SAIA") {
                TextField("Usuario", text: $settings.username)
                SecureField("Contraseña", text: $settings.password,
                            prompt: Text(settings.hasStoredCredentials ? "Guardada en el llavero" : "Contraseña"))
                HStack {
                    Button("Guardar en el llavero") { settings.saveCredentials() }
                    Button("Eliminar", role: .destructive) { settings.deleteCredentials() }
                        .disabled(!settings.hasStoredCredentials)
                }
                if let message = settings.statusMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text("Las credenciales se almacenan solo en el llavero de macOS y se pasan al script únicamente como variables de entorno del proceso.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 980)
        .onChange(of: settings.workspacePath) { _, _ in Task { await container.workspace.reload() } }
        .task(id: settings.pythonPath) { await settings.validatePython() }
        .task(id: settings.binaryPaths) {
            try? await Task.sleep(for: .milliseconds(400)) // debounce typing; cancelled when the paths change again
            guard !Task.isCancelled else { return }
            for provider in AgentProviderID.allCases { await settings.refreshStatus(provider) }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = container.settings.workspaceURL
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url { container.settings.workspacePath = url.path }
    }
}

/// Binary path, status, default model and permission level of one provider.
private struct ProviderSettingsSection: View {
    let provider: AgentProviderID
    @Bindable var settings: SettingsModel

    private var pathBinding: Binding<String> {
        Binding(get: { settings.binaryPaths[provider] ?? "" }, set: { settings.binaryPaths[provider] = $0 })
    }

    private var modelBinding: Binding<String> {
        Binding(get: { settings.defaultModels[provider] ?? "" }, set: { settings.defaultModels[provider] = $0 })
    }

    private var permissionBinding: Binding<AgentPermissionLevel> {
        Binding(get: { provider.normalized(settings.defaultPermissions[provider] ?? .acceptEdits) },
                set: { settings.defaultPermissions[provider] = $0 })
    }

    var body: some View {
        Section {
            HStack {
                TextField("Ejecutable", text: pathBinding,
                          prompt: Text("Automático (\(provider.binaryName))"))
                Button("Detectar") { Task { await settings.detect(provider) } }
            }
            statusLine
            modelControls
            Picker("Modo de permisos", selection: permissionBinding) {
                ForEach(provider.supportedPermissions) { Text($0.label).tag($0) }
            }
            let level = provider.normalized(settings.defaultPermissions[provider] ?? .acceptEdits)
            Text(level.detail(for: provider)).font(.caption).foregroundStyle(.secondary)
            if level == .unrestricted {
                Label("Con «Sin restricciones» el agente puede modificar o borrar cualquier archivo y ejecutar comandos sin pedir permiso.",
                      systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if let warning = provider.tosWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Label { Text(provider.displayName) } icon: { AgentProviderMark(provider: provider, size: 14) }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch settings.statuses[provider] {
        case .checking?:
            Label("Comprobando…", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
        case .found(let path, let version)?:
            Label("Encontrado\(version.map { " · v\($0)" } ?? ""): \(path)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green).lineLimit(2).truncationMode(.middle)
        case .invalidOverride?:
            Label("La ruta no existe o no es ejecutable.", systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
            installHint
        case .notInstalled?:
            Label("No instalado", systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
            installHint
        case nil:
            EmptyView()
        }
    }

    private var installHint: some View {
        HStack(spacing: 8) {
            Text(provider.installHint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Spacer(minLength: 0)
            if provider.installHintIsCommand {
                Button("Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(provider.installHint, forType: .string)
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var modelControls: some View {
        let options = settings.modelOptions(for: provider)
        let current = settings.defaultModels[provider] ?? ""
        switch provider.modelSource {
        case .fixed:
            Picker("Modelo predeterminado", selection: modelBinding) {
                ForEach(options) { Text($0.label).tag($0.key) }
            }
        case .listed(let allowsCustom):
            if allowsCustom {
                TextField("Modelo predeterminado", text: modelBinding,
                          prompt: Text("proveedor/modelo (vacío = el de OpenCode)"))
            } else {
                Picker("Modelo predeterminado", selection: modelBinding) {
                    ForEach(options) { Text($0.label).tag($0.key) }
                    if !current.isEmpty, !options.contains(where: { $0.key == current }) { Text(current).tag(current) }
                }
            }
            HStack {
                if allowsCustom, options.count > 1 {
                    Menu("Elegir de la lista") {
                        ForEach(options.filter { $0.id != nil }.prefix(60)) { item in
                            Button(item.label) { settings.defaultModels[provider] = item.key }
                        }
                    }
                    .fixedSize()
                }
                Button(settings.loadingModels.contains(provider) ? "Cargando…" : "Cargar modelos") {
                    Task { await settings.loadModels(for: provider) }
                }
                .disabled(settings.loadingModels.contains(provider))
                Text("\(max(0, options.count - 1)) modelos disponibles").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Deadline notification preferences, permission state and a test button.
private struct RemindersSection: View {
    @Environment(AppContainer.self) private var container
    @Bindable var settings: SettingsModel

    var body: some View {
        Section("Recordatorios de entregas") {
            Toggle("Avisarme antes de cada entrega", isOn: $settings.reminders.enabled)
            if settings.reminders.enabled {
                Toggle("48 horas antes", isOn: $settings.reminders.at48h)
                Toggle("24 horas antes", isOn: $settings.reminders.at24h)
                Toggle("3 horas antes", isOn: $settings.reminders.at3h)
                Toggle("Aviso personalizado", isOn: $settings.reminders.customEnabled)
                if settings.reminders.customEnabled {
                    Stepper("\(settings.reminders.customHours) h antes", value: $settings.reminders.customHours, in: 1...336)
                }
                permissionStatus
                HStack {
                    Button("Enviar notificación de prueba") { Task { await container.reminders.sendTest() } }
                    Spacer()
                    Text("\(container.reminders.scheduledCount) programados").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Se programan como máximo \(DeadlineReminderPlanner.maxPending) avisos, los más cercanos primero. Las actividades entregadas no generan avisos.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await container.reminders.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await container.reminders.refreshPermission() }
        }
    }

    @ViewBuilder
    private var permissionStatus: some View {
        switch container.reminders.permission {
        case .denied:
            Label("Las notificaciones de Cátedra están desactivadas en el sistema.", systemImage: "bell.slash.fill")
                .font(.caption).foregroundStyle(.orange)
            Button("Abrir Ajustes del Sistema") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
            }
        case .notDetermined:
            Label("El sistema pedirá permiso al programar el primer aviso.", systemImage: "bell.badge")
                .font(.caption).foregroundStyle(.secondary)
        case .authorized:
            Label("Notificaciones permitidas.", systemImage: "bell.fill").font(.caption).foregroundStyle(.green)
        }
    }
}
