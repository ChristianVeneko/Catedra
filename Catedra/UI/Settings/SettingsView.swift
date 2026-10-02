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
        .frame(width: 540, height: 500)
        .onChange(of: settings.workspacePath) { _, _ in Task { await container.workspace.reload() } }
        .task(id: settings.pythonPath) { await settings.validatePython() }
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
