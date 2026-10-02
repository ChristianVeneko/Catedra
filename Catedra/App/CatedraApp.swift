import SwiftUI

@main
struct CatedraApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup("Cátedra") {
            ContentView()
                .environment(container)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Sincronizar") { container.sync.start(includeFiles: true) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Sincronizar sin archivos") { container.sync.start(includeFiles: false) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView().environment(container)
        }
    }
}
