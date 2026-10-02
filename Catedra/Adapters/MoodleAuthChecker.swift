import Foundation

/// POSTs the credentials to SAIA's `login/token.php` (`service=moodle_mobile_app`). The returned token is discarded;
/// neither the password nor the token is logged or stored.
struct MoodleAuthChecker: MoodleAuthChecking {
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func check(username: String, password: String) async -> MoodleAuthResult {
        do {
            let (data, _) = try await session.data(for: MoodleAuthRequest.make(username: username, password: password))
            return MoodleAuthResponse.parse(data)
        } catch {
            return .unreachable((error as? URLError)?.localizedDescription ?? "error de red")
        }
    }
}
