import Foundation

/// The only folders inside an activity where the app may write user files.
enum ImportTarget: String, CaseIterable, Identifiable, Sendable {
    case entrega, preparacion, apuntes

    var id: String { rawValue }
    var folderName: String { rawValue }

    var label: String {
        switch self {
        case .entrega: "Entrega"
        case .preparacion: "Preparación"
        case .apuntes: "Apuntes"
        }
    }
}
