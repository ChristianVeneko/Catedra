import Foundation

enum PaletteSection: Int, CaseIterable, Sendable {
    case recents, activities, courses, contents, actions, recipes

    var title: String {
        switch self {
        case .recents: "Recientes"
        case .activities: "Actividades"
        case .courses: "Materias"
        case .contents: "Contenidos"
        case .actions: "Acciones"
        case .recipes: "Recetas"
        }
    }

    /// Maximum rows per section while searching.
    var limit: Int {
        switch self {
        case .recents: 10
        case .activities: 6
        case .courses: 5
        case .contents: 6
        case .actions: 6
        case .recipes: 4
        }
    }
}

enum PaletteAction: Hashable, Sendable {
    case openActivity(String)
    case openCourse(String)
    case openCourseAgent(String)
    /// `path` is the absolute file path inside the workspace.
    case openContent(courseFolder: String, path: String)
    case sync(includeFiles: Bool)
    case openSettings
    case openOnboarding
    case showToday
    case setProvider(AgentProviderID)
    /// Opens the agent panel of the scope with the recipe prompt prefilled (never runs it).
    case runRecipe(recipeID: String, scopeFolder: String, isCourse: Bool)
}

struct PaletteItem: Identifiable, Hashable, Sendable {
    let id: String
    let section: PaletteSection
    let title: String
    let subtitle: String
    let symbol: String
    let action: PaletteAction
    /// Course whose accent color tints the row, if any.
    let courseFolder: String?
    let foldedTitle: [Character]
    let foldedExtra: [Character]

    init(id: String, section: PaletteSection, title: String, subtitle: String = "", keywords: String = "",
         symbol: String, action: PaletteAction, courseFolder: String? = nil) {
        self.id = id
        self.section = section
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.action = action
        self.courseFolder = courseFolder
        self.foldedTitle = PaletteMatcher.fold(title)
        self.foldedExtra = PaletteMatcher.fold(subtitle + " " + keywords)
    }
}

struct PaletteGroup: Identifiable, Equatable, Sendable {
    let section: PaletteSection
    let items: [PaletteItem]
    var id: Int { section.rawValue }
}
