import SwiftUI

@main
struct CatedraApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        Window("Cátedra", id: AppContainer.mainWindowID) {
            ContentView()
                .environment(container)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            OnboardingCommands()
            CommandMenu("Ir") {
                Button("Buscar…") {
                    container.showMainWindow()
                    container.palette.present()
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("Hoy") { container.navigation.sidebar = .today }
                    .keyboardShortcut("1", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Sincronizar") { container.sync.start(includeFiles: true) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Sincronizar sin archivos") { container.sync.start(includeFiles: false) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }

        Window("Asistente de configuración", id: "onboarding") {
            OnboardingView().environment(container)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        MenuBarExtra(isInserted: Binding(get: { container.settings.menuBarVisible },
                                         set: { container.settings.menuBarVisible = $0 })) {
            MenuBarPopover().environment(container)
        } label: {
            MenuBarLabelView().environment(container)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(container)
        }
    }
}

/// App-menu entry that re-runs the setup wizard.
struct OnboardingCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Asistente de configuración…") { openWindow(id: "onboarding") }
        }
    }
}
