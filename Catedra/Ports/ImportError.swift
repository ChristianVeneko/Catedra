import Foundation

enum ImportError: Error, Equatable, LocalizedError {
    case outsideWorkspace
    case notADirectory
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .outsideWorkspace: "La carpeta de destino está fuera del espacio de trabajo."
        case .notADirectory: "La carpeta de la actividad no existe."
        case .copyFailed(let name): "No se pudo copiar «\(name)»."
        }
    }
}
