import Foundation

/// Kind of Moodle activity. Unknown types are preserved verbatim in `.other`.
enum ActivityKind: Hashable, Sendable {
    case tarea
    case cuestionario
    case examen
    case other(String)

    init(rawType: String) {
        switch rawType {
        case "Tarea": self = .tarea
        case "Cuestionario": self = .cuestionario
        case "Examen": self = .examen
        default: self = .other(rawType)
        }
    }

    var symbolName: String {
        switch self {
        case .tarea: "doc.text"
        case .cuestionario: "checklist"
        case .examen: "graduationcap"
        case .other: "circle"
        }
    }

    /// Spanish display label.
    var displayName: String {
        switch self {
        case .tarea: "Tarea"
        case .cuestionario: "Cuestionario"
        case .examen: "Examen"
        case .other(let raw): raw
        }
    }

    /// Folder that receives student work by default for this kind.
    var defaultImportTarget: ImportTarget {
        switch self {
        case .tarea: .entrega
        case .cuestionario, .examen: .preparacion
        case .other: .apuntes
        }
    }
}
