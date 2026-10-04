import Foundation

protocol GradeSettingsStoring: Sendable {
    func load() -> GradeSettings
    func save(_ settings: GradeSettings) throws
}
