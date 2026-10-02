import Foundation
import Observation

/// State of the ⌘K command palette: query, ranked groups and keyboard selection.
@Observable @MainActor
final class PaletteModel {
    private(set) var isPresented = false
    var query = "" { didSet { if query != oldValue { selectedID = nil; rebuild() } } }
    private(set) var groups: [PaletteGroup] = []
    var selectedID: String?
    private(set) var recents: PaletteRecents

    /// Static items (activities, courses, contents, actions); the owner supplies them.
    var itemsProvider: @MainActor () -> [PaletteItem] = { [] }
    /// Recipe rows for the current query.
    var recipeProvider: @MainActor (String) -> [PaletteItem] = { _ in [] }
    var perform: @MainActor (PaletteAction) -> Void = { _ in }
    var onPresent: @MainActor () -> Void = {}

    private let defaults: UserDefaults
    private var baseItems: [PaletteItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recents = PaletteRecents.load(from: defaults)
    }

    var flatItems: [PaletteItem] { groups.flatMap(\.items) }

    func present() {
        query = ""
        refreshItems()
        isPresented = true
        onPresent()
    }

    func toggle() { isPresented ? dismiss() : present() }

    func dismiss() { isPresented = false }

    /// Re-reads the static items (workspace or content index changed while the palette is open).
    func refreshItems() {
        baseItems = itemsProvider()
        rebuild()
    }

    func move(_ delta: Int) {
        let items = flatItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : items.count)
        selectedID = items[min(max(current + delta, 0), items.count - 1)].id
    }

    func activateSelected() {
        guard let item = flatItems.first(where: { $0.id == selectedID }) ?? flatItems.first else { return }
        activate(item)
    }

    func activate(_ item: PaletteItem) {
        recents.record(item.id)
        recents.save(to: defaults)
        dismiss()
        perform(item.action)
    }

    private func rebuild() {
        let recipes = recipeProvider(query)
        groups = PaletteMatcher.results(query: query, items: baseItems + recipes, recentIDs: recents.ids)
        let ids = flatItems.map(\.id)
        if let selectedID, ids.contains(selectedID) { return }
        selectedID = ids.first
    }
}
