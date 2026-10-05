import Foundation
import Observation

/// State of the ⌘K command palette: query, ranked groups and keyboard selection.
@Observable @MainActor
final class PaletteModel {
    private(set) var isPresented = false
    var query = "" { didSet { if query != oldValue { selectedID = nil; rebuild(); scheduleContentSearch() } } }
    private(set) var groups: [PaletteGroup] = []
    var selectedID: String?
    private(set) var recents: PaletteRecents

    /// Static items (activities, courses, contents, actions); the owner supplies them.
    var itemsProvider: @MainActor () -> [PaletteItem] = { [] }
    /// Recipe rows for the current query.
    var recipeProvider: @MainActor (String) -> [PaletteItem] = { _ in [] }
    var perform: @MainActor (PaletteAction) -> Void = { _ in }
    var onPresent: @MainActor () -> Void = {}
    /// Full-text search over the indexed contents; the owner supplies it.
    var contentSearch: @MainActor (String) async -> [ContentSearchHit] = { _ in [] }
    /// Courses used to label full-text rows.
    var coursesProvider: @MainActor () -> [Course] = { [] }
    /// Attaches the files behind the shown full-text results to an agent composer.
    var attachHits: @MainActor ([ContentSearchHit]) -> Void = { _ in }
    static let searchDebounce: Duration = .milliseconds(250)
    private(set) var contentHits: [ContentSearchHit] = []
    private(set) var isSearchingContent = false
    private var searchTask: Task<Void, Never>?

    private let defaults: UserDefaults
    private var baseItems: [PaletteItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recents = PaletteRecents.load(from: defaults)
    }

    var flatItems: [PaletteItem] { groups.flatMap(\.items) }

    func present() {
        query = ""
        contentHits = []
        refreshItems()
        isPresented = true
        onPresent()
    }

    func toggle() { isPresented ? dismiss() : present() }

    func dismiss() {
        isPresented = false
        searchTask?.cancel()
        isSearchingContent = false
    }

    /// Hits behind the "Contenido" rows currently shown.
    var shownContentHits: [ContentSearchHit] {
        ContentSearchHit.diversified(contentHits, perFile: 2, total: PaletteSection.fullText.limit)
    }

    func askAgentAboutResults() {
        let hits = shownContentHits
        guard !hits.isEmpty else { return }
        dismiss()
        attachHits(hits)
    }

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

    /// Debounced full-text search; an unusable query clears the hits immediately.
    private func scheduleContentSearch() {
        searchTask?.cancel()
        guard SearchQuerySanitizer.matchExpression(from: query) != nil else {
            isSearchingContent = false
            if !contentHits.isEmpty { contentHits = []; rebuild() }
            return
        }
        isSearchingContent = true
        let text = query
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled, let self else { return }
            let hits = await contentSearch(text)
            guard !Task.isCancelled, query == text else { return }
            contentHits = hits
            isSearchingContent = false
            rebuild()
        }
    }

    private func rebuild() {
        let recipes = recipeProvider(query)
        var built = PaletteMatcher.results(query: query, items: baseItems + recipes, recentIDs: recents.ids)
        let hitItems = PaletteCatalog.contentHitItems(contentHits, courses: coursesProvider())
        if !hitItems.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            built.append(PaletteGroup(section: .fullText, items: hitItems))
            built.sort { $0.section.rawValue < $1.section.rawValue }
        }
        groups = built
        let ids = flatItems.map(\.id)
        if let selectedID, ids.contains(selectedID) { return }
        selectedID = ids.first
    }
}
