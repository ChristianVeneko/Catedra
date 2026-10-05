import Foundation

/// One app-owned JSON document under Application Support. `load` returns nil when missing or unreadable.
protocol StateStoring<Value>: Sendable {
    associatedtype Value: Codable & Sendable
    func load() -> Value?
    func save(_ value: Value) throws
}
