import Foundation

protocol ReviewProgressStoring: Sendable {
    func load() -> ReviewProgressFile
    func save(_ file: ReviewProgressFile) throws
}
