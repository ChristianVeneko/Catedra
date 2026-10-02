import Foundation

enum SyncLogEvent: Equatable, Sendable {
    case course(String)
    case done(activities: Int)
    case loginFailed(String)
    case warning(String)
    case info(String)
    case ignored
}

/// Classifies lines printed by `sync_moodle.py`.
enum SyncLogParser {
    static func parse(_ line: String, isError: Bool) -> SyncLogEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .ignored }
        if trimmed.hasPrefix("Login failed") {
            let detail = trimmed.dropFirst("Login failed".count).drop(while: { $0 == ":" || $0 == " " })
            return .loginFailed(String(detail))
        }
        if trimmed.hasPrefix("> ") { return .course(String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("Done:") {
            let digits = trimmed.dropFirst(5).drop(while: { $0 == " " }).prefix(while: \.isNumber)
            return .done(activities: Int(digits) ?? 0)
        }
        if trimmed.hasPrefix("! ") { return .warning(String(trimmed.dropFirst(2))) }
        return isError ? .warning(trimmed) : .info(trimmed)
    }
}
