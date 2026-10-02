import Foundation

enum MoodleAuthResult: Sendable, Equatable {
    case success
    case invalidCredentials
    case serviceUnavailable
    /// SAIA answered with another error; carries its message.
    case rejected(String)
    /// The request never got an answer (offline, timeout, TLS…).
    case unreachable(String)

    var isSuccess: Bool { self == .success }

    var message: String {
        switch self {
        case .success: "Conexión correcta: SAIA aceptó las credenciales."
        case .invalidCredentials: "Usuario o contraseña incorrectos."
        case .serviceUnavailable: "El servicio móvil de SAIA no está disponible en este momento."
        case .rejected(let detail): "SAIA rechazó la solicitud: \(detail)"
        case .unreachable(let detail): "No se pudo conectar con SAIA: \(detail)"
        }
    }
}

/// Maps the JSON of `login/token.php` to a result. The token itself is never kept.
enum MoodleAuthResponse {
    static func parse(_ data: Data) -> MoodleAuthResult {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .rejected("Respuesta inesperada de SAIA.")
        }
        if let token = json["token"] as? String, !token.isEmpty { return .success }
        if let code = json["errorcode"] as? String {
            switch code {
            case "invalidlogin": return .invalidCredentials
            case "enablewsdescription", "servicenotavailable", "webservicesnotenabled": return .serviceUnavailable
            default: break
            }
        }
        if let error = json["error"] as? String, !error.isEmpty { return .rejected(error) }
        return .rejected("Respuesta inesperada de SAIA.")
    }
}

enum MoodleAuthRequest {
    static let endpoint = URL(string: "https://saia.uft.edu.ve/login/token.php")!
    static let service = "moodle_mobile_app"

    static func make(username: String, password: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [("username", username), ("password", password), ("service", service)]
            .map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        request.httpBody = Data(body.utf8)
        return request
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
