import Foundation

/// Ids of the last items opened from the palette, newest first.
struct PaletteRecents: Equatable, Sendable {
    static let limit = 10
    private(set) var ids: [String] = []

    init(ids: [String] = []) { self.ids = Array(ids.prefix(Self.limit)) }

    mutating func record(_ id: String) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > Self.limit { ids.removeLast(ids.count - Self.limit) }
    }

    private static let key = "paletteRecents"

    static func load(from defaults: UserDefaults = .standard) -> PaletteRecents {
        PaletteRecents(ids: defaults.stringArray(forKey: key) ?? [])
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(ids, forKey: Self.key)
    }
}
