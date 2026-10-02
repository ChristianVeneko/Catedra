import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

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
            Section("Python") {
                HStack {
                    TextField("Intérprete", text: $settings.pythonPath, prompt: Text("/opt/homebrew/bin/python3"))
                    Button("Detectar") { Task { await settings.detectPython() } }
                }
                if let status = settings.pythonStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                Text("Debe tener instalado el módulo «requests».").font(.caption).foregroundStyle(.secondary)
            }
            Section("Agentes (Claude Code)") {
                HStack {
                    TextField("Ejecutable", text: $settings.claudePath, prompt: Text("/Users/…/.local/bin/claude"))
                    Button("Detectar") { Task { await settings.detectClaude() } }
                }
                if let status = settings.claudeStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                Picker("Modelo predeterminado", selection: $settings.agentModel) {
                    ForEach(AgentModel.allCases) { Text($0.label).tag($0) }
                }
                Picker("Modo de permisos", selection: $settings.agentPermissionMode) {
                    ForEach(AgentPermissionMode.allCases) { Text($0.label).tag($0) }
                }
                Text(settings.agentPermissionMode.detail).font(.caption).foregroundStyle(.secondary)
                if settings.agentPermissionMode == .bypassPermissions {
                    Label("Con «Sin restricciones» el agente puede modificar o borrar cualquier archivo y ejecutar comandos sin pedir permiso.",
                          systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
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
        .frame(width: 540, height: 700)
        .onChange(of: settings.workspacePath) { _, _ in Task { await container.workspace.reload() } }
        .task(id: settings.pythonPath) { await settings.validatePython() }
        .task(id: settings.claudePath) { settings.validateClaude() }
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
