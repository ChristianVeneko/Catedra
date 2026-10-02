import Testing
import Foundation
@testable import Catedra

struct PaletteMatcherTests {
    func item(_ title: String, section: PaletteSection = .activities, subtitle: String = "", keywords: String = "",
              id: String? = nil) -> PaletteItem {
        PaletteItem(id: id ?? "\(section.rawValue):\(title)", section: section, title: title, subtitle: subtitle, keywords: keywords,
                    symbol: "circle", action: .showToday)
    }

    func titles(_ groups: [PaletteGroup]) -> [String] { groups.flatMap(\.items).map(\.title) }

    @Test func ranksPrefixOverBoundaryOverSubstringOverExtraOverSubsequence() {
        let items = [
            item("Xparcialx"),                       // substring 500
            item("Examen parcial"),                  // boundary 600
            item("Parcial 1"),                       // prefix 1000
            item("Otra", subtitle: "tiene parcial"), // extra 300
            item("pxaxrxc"),                         // subsequence 100
        ]
        #expect(titles(PaletteMatcher.results(query: "parc", items: items))
                == ["Parcial 1", "Examen parcial", "Xparcialx", "Otra", "pxaxrxc"])
        #expect(titles(PaletteMatcher.results(query: "pzc", items: [item("pxaxrxc")])).isEmpty)
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(titles(PaletteMatcher.results(query: "ANALISIS", items: [item("Análisis de señales")])) == ["Análisis de señales"])
        #expect(titles(PaletteMatcher.results(query: "senales", items: [item("Análisis de señales")])) == ["Análisis de señales"])
    }

    @Test func everyWordMustMatch() {
        let items = [item("Tarea 1", subtitle: "Teoría de Control II"), item("Tarea 2", subtitle: "Software")]
        #expect(titles(PaletteMatcher.results(query: "tarea control", items: items)) == ["Tarea 1"])
        #expect(titles(PaletteMatcher.results(query: "tarea zzz", items: items)).isEmpty)
    }

    @Test func groupsFollowFixedSectionOrderAndKeepInputOrderOnTies() {
        let items = [
            item("Sincronizar", section: .actions),
            item("Sin título b", section: .activities, id: "b"),
            item("Sin título a", section: .activities, id: "a"),
            item("Sintonía", section: .courses),
        ]
        let groups = PaletteMatcher.results(query: "sin", items: items)
        #expect(groups.map(\.section) == [.activities, .courses, .actions])
        #expect(groups[0].items.map(\.id) == ["b", "a"])
    }

    @Test func limitsEachSection() {
        let items = (0..<20).map { item("Tarea \($0)", id: "t\($0)") }
        let groups = PaletteMatcher.results(query: "tarea", items: items)
        #expect(groups.first?.items.count == PaletteSection.activities.limit)
    }

    @Test func exactTitleBeatsLongerPrefixMatches() {
        let items = [item("Ajustes avanzados"), item("Ajustes")]
        #expect(titles(PaletteMatcher.results(query: "ajustes", items: items)).first == "Ajustes")
    }

    @Test func emptyQueryShowsRecentsInOrderOrFallsBackToActions() {
        let a = item("A", id: "a"), b = item("B", id: "b"), act = item("Sincronizar", section: .actions, id: "act")
        let groups = PaletteMatcher.results(query: " ", items: [a, b, act], recentIDs: ["b", "gone", "a"])
        #expect(groups.map(\.section) == [.recents])
        #expect(groups[0].items.map(\.id) == ["b", "a"])
        let fallback = PaletteMatcher.results(query: "", items: [a, b, act])
        #expect(fallback.map(\.section) == [.actions])
    }
}

struct PaletteRecentsTests {
    @Test func recordsNewestFirstWithoutDuplicates() {
        var r = PaletteRecents()
        r.record("a"); r.record("b"); r.record("a")
        #expect(r.ids == ["a", "b"])
    }

    @Test func keepsOnlyTheLastTen() {
        var r = PaletteRecents()
        for i in 0..<15 { r.record("i\(i)") }
        #expect(r.ids.count == 10)
        #expect(r.ids.first == "i14")
        #expect(r.ids.last == "i5")
    }

    @Test func persistsInUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "catedra.tests.palette.\(UUID().uuidString)"))
        var r = PaletteRecents()
        r.record("x"); r.record("y")
        r.save(to: defaults)
        #expect(PaletteRecents.load(from: defaults).ids == ["y", "x"])
    }
}

struct PaletteCatalogTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let courses = [Course(folderName: "08 - Teoria de Control II")!, Course(folderName: "02 - Diseno de Software")!]

    func activities() -> [Activity] {
        [
            makeActivity(course: "Teoria de Control II", kind: .examen, name: "Parcial No. 1", due: now.addingTimeInterval(86400),
                         folder: "08 - Teoria de Control II/actividades/Examen - Parcial No. 1"),
            makeActivity(course: "Teoria de Control II", kind: .tarea, name: "Informe final", due: now.addingTimeInterval(2 * 86400),
                         folder: "08 - Teoria de Control II/actividades/Tarea - Informe final"),
            makeActivity(course: "Diseno de Software", kind: .cuestionario, name: "Quiz patrones", due: now.addingTimeInterval(3 * 86400),
                         folder: "02 - Diseno de Software/actividades/Cuestionario - Quiz patrones"),
        ]
    }

    func state(_ a: Activity) -> ActivityState { ActivityState.derive(from: a, hasUserWork: false, now: now) }

    func recipes(_ query: String, context: Activity? = nil, course: Course? = nil) -> [PaletteItem] {
        PaletteCatalog.recipeItems(query: query, activities: activities(), courses: courses, contextActivity: context,
                                   contextCourse: course, stateOf: state, now: now)
    }

    @Test func buildsAllSectionsAndSkipsTheCurrentProvider() {
        let entry = ContentIndexEntry(courseFolder: courses[0].folderName, courseName: "Teoria de Control II",
                                      url: URL(fileURLWithPath: "/ws/08/contenidos/u1/tema.pdf"), name: "tema.pdf", parentPath: "u1")
        let items = PaletteCatalog.items(activities: activities(), courses: courses, contents: [entry], provider: .claude)
        #expect(items.filter { $0.section == .activities }.count == 3)
        #expect(items.filter { $0.section == .courses }.count == 4)
        #expect(items.filter { $0.section == .contents }.map(\.title) == ["tema.pdf"])
        let providerTitles = items.filter { $0.id.hasPrefix("action:provider:") }.map(\.title)
        #expect(providerTitles == ["Cambiar agente a Antigravity", "Cambiar agente a OpenCode"])
        let actionTitles = items.filter { $0.section == .actions }.map(\.title)
        #expect(actionTitles.contains("Sincronizar") && actionTitles.contains("Sincronizar sin archivos"))
        #expect(actionTitles.contains("Ajustes") && actionTitles.contains("Asistente de configuración") && actionTitles.contains("Mostrar Hoy"))
    }

    @Test func courseAgentItemTargetsTheCourse() {
        let items = PaletteCatalog.items(activities: [], courses: courses, contents: [], provider: .claude)
        let agent = items.first { $0.title == "Agente de Teoria de Control II" }
        #expect(agent?.action == .openCourseAgent("08 - Teoria de Control II"))
    }

    @Test func recipeUsesTheSelectedActivityWhenApplicable() {
        let selected = activities()[0] // examen
        let items = recipes("guia", context: selected)
        #expect(items.map(\.title) == ["Ejecutar Guía de estudio en Parcial No. 1"])
        #expect(items.first?.action == .runRecipe(recipeID: "study-guide", scopeFolder: selected.folder, isCourse: false))
    }

    @Test func recipeFallsBackToTheNearestOpenApplicableActivity() {
        #expect(recipes("simulacro").map(\.title) == ["Ejecutar Simulacro con corrección en Parcial No. 1"])
        #expect(recipes("plan de trabajo").map(\.title) == ["Ejecutar Plan de trabajo en Informe final"])
    }

    @Test func leftoverWordsPickTheMatchingActivity() {
        let items = recipes("guia quiz")
        #expect(items.map(\.title) == ["Ejecutar Guía de estudio en Quiz patrones"])
    }

    @Test func courseRecipesUseTheContextCourse() {
        #expect(recipes("resumen materia").isEmpty)
        let items = recipes("resumen materia", course: courses[1])
        #expect(items.map(\.title) == ["Ejecutar Resumen de la materia en Diseno de Software"])
        #expect(items.first?.action == .runRecipe(recipeID: "course-summary", scopeFolder: courses[1].folderName, isCourse: true))
    }

    @Test func nonRecipeQueriesProduceNoRecipeRows() {
        #expect(recipes("parcial").isEmpty)
        #expect(recipes("").isEmpty)
    }

    @Test func recipeRowsAreFoundByTheMatcherWithTheirTarget() {
        let rows = recipes("guia", context: activities()[0])
        let groups = PaletteMatcher.results(query: "guia", items: rows)
        #expect(groups.map(\.section) == [.recipes])
    }
}

struct ContentIndexTests {
    struct StubReader: WorkspaceReading {
        var tree: [ContentNode]
        func loadSnapshot(root: URL) throws -> WorkspaceSnapshot { .empty }
        func files(root: URL, activity: Activity) -> ActivityFiles { ActivityFiles() }
        func contentTree(root: URL, course: Course) -> [ContentNode] { tree }
        func forums(root: URL, course: Course) -> [ContentNode] { [] }
    }

    func node(_ path: String, dir: Bool = false, children: [ContentNode]? = nil) -> ContentNode {
        ContentNode(url: URL(fileURLWithPath: "/ws/" + path), name: (path as NSString).lastPathComponent, isDirectory: dir, children: children)
    }

    @Test func flattensFilesWithTheirFolderAndExcludesImageFolders() {
        let tree = [
            node("c/contenidos/intro.md"),
            node("c/contenidos/u1", dir: true, children: [
                node("c/contenidos/u1/tema.pdf"),
                node("c/contenidos/u1/_imagenes", dir: true, children: [node("c/contenidos/u1/_imagenes/blob.jpg")]),
                node("c/contenidos/u1/sub", dir: true, children: [node("c/contenidos/u1/sub/deep.md")]),
            ]),
            node("c/contenidos/_imagenes", dir: true, children: [node("c/contenidos/_imagenes/x.png")]),
        ]
        let course = Course(folderName: "01 - Calculo")!
        let entries = ContentIndexBuilder.entries(root: URL(fileURLWithPath: "/ws"), courses: [course], reader: StubReader(tree: tree))
        #expect(entries.map(\.name) == ["intro.md", "tema.pdf", "deep.md"])
        #expect(entries.map(\.parentPath) == ["", "u1", "u1/sub"])
        #expect(entries.allSatisfy { $0.courseFolder == "01 - Calculo" && $0.courseName == "Calculo" })
    }
}
