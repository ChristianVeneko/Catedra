import Foundation

/// `catedra://guion/...` links, used by the agent (`open -g "<link>"`) and the palette to drive the teleprompter.
/// Only Markdown files inside the workspace are accepted, so a link from elsewhere cannot read arbitrary files.
enum ScriptLink: Equatable {
    case start(URL)
    case stop
    /// A `guion` link with a bad or missing file; the message is shown to the user.
    case invalid(String)

    static let host = "guion"

    static func parse(_ url: URL, workspace: URL) -> ScriptLink? {
        guard url.scheme == WidgetLink.scheme, url.host() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "cerrar", "detener":
            return .stop
        case "activar", "abrir", "":
            guard let raw = components.queryItems?.first(where: { $0.name == "archivo" })?.value, !raw.isEmpty else {
                return .invalid("Falta el parámetro «archivo» del guion.")
            }
            let rootPath = workspace.standardizedFileURL.path
            let candidate = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : URL(fileURLWithPath: rootPath).appending(path: raw)
            let file = URL(fileURLWithPath: candidate.standardizedFileURL.path)
            guard file.path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
                return .invalid("El guion debe estar dentro de la carpeta de Cátedra.")
            }
            guard file.pathExtension.lowercased() == "md" else { return .invalid("El guion debe ser un archivo .md.") }
            return .start(file)
        default:
            return nil
        }
    }

    static func startURL(for file: URL) -> URL {
        var components = URLComponents()
        components.scheme = WidgetLink.scheme
        components.host = host
        components.path = "/activar"
        components.queryItems = [URLQueryItem(name: "archivo", value: file.path)]
        return components.url!
    }
}
