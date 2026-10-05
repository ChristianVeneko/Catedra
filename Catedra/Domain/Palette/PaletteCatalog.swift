import Foundation

/// Builds the searchable items of the palette from the current workspace. Pure.
enum PaletteCatalog {
    static func items(activities: [Activity], courses: [Course], contents: [ContentIndexEntry],
                      provider: AgentProviderID) -> [PaletteItem] {
        var items: [PaletteItem] = []
        for activity in activities {
            items.append(PaletteItem(
                id: "activity:\(activity.id)", section: .activities, title: activity.name,
                subtitle: "\(activity.courseName) · \(activity.kind.displayName)",
                symbol: activity.kind.symbolName, action: .openActivity(activity.id), courseFolder: activity.courseFolderName))
        }
        for course in courses {
            items.append(PaletteItem(
                id: "course:\(course.folderName)", section: .courses, title: course.name, subtitle: "Abrir materia",
                symbol: "book.closed", action: .openCourse(course.folderName), courseFolder: course.folderName))
            items.append(PaletteItem(
                id: "agent:\(course.folderName)", section: .courses, title: "Agente de \(course.name)",
                subtitle: "Conversación con el agente de la materia", keywords: "asistente ia",
                symbol: "sparkles", action: .openCourseAgent(course.folderName), courseFolder: course.folderName))
        }
        for entry in contents {
            let place = entry.parentPath.isEmpty ? entry.courseName : "\(entry.courseName) · \(entry.parentPath)"
            items.append(PaletteItem(
                id: "content:\(entry.url.path)", section: .contents, title: entry.name, subtitle: place,
                symbol: fileSymbol(entry.url), action: .openContent(courseFolder: entry.courseFolder, path: entry.url.path),
                courseFolder: entry.courseFolder))
        }
        items += actions(provider: provider)
        return items
    }

    /// Rows of the "Contenido" section for full-text hits (at most two per file).
    static func contentHitItems(_ hits: [ContentSearchHit], courses: [Course]) -> [PaletteItem] {
        let limit = PaletteSection.fullText.limit
        return ContentSearchHit.diversified(hits, perFile: 2, total: limit).map { hit in
            let course = courses.first { $0.folderName == hit.courseFolder }?.name ?? hit.courseFolder
            let title = hit.page.map { "\(hit.fileName) · p. \($0)" } ?? hit.fileName
            return PaletteItem(
                id: "hit:\(hit.id)", section: .fullText, title: title, subtitle: course, symbol: fileSymbol(hit.url),
                action: .openContentHit(courseFolder: hit.courseFolder, path: hit.url.path, page: hit.page),
                courseFolder: hit.courseFolder, snippet: hit.snippet)
        }
    }

    static func actions(provider: AgentProviderID) -> [PaletteItem] {
        var result = [
            PaletteItem(id: "action:today", section: .actions, title: "Mostrar Hoy", subtitle: "Agenda y próximas entregas",
                        keywords: "inicio agenda", symbol: "sun.max", action: .showToday),
            PaletteItem(id: "action:calendar", section: .actions, title: "Abrir calendario",
                        subtitle: "Entregas, clases y bloques de estudio", keywords: "agenda semana mes planificador",
                        symbol: "calendar", action: .openCalendar),
            PaletteItem(id: "action:grades", section: .actions, title: "Abrir notas",
                        subtitle: "Puntos acumulados y simulador por materia", keywords: "calificaciones puntos aprobar simulador",
                        symbol: "chart.bar.doc.horizontal", action: .openGrades),
            PaletteItem(id: "action:review", section: .actions, title: "Repasar tarjetas",
                        subtitle: "Tarjetas de repaso y cuestionarios de práctica", keywords: "repaso flashcards estudiar cuestionario",
                        symbol: "rectangle.on.rectangle", action: .openReview),
            PaletteItem(id: "action:study-block", section: .actions, title: "Nuevo bloque de estudio",
                        subtitle: "Planificar tiempo de estudio", keywords: "calendario estudiar planificar",
                        symbol: "book", action: .newStudyBlock),
            PaletteItem(id: "action:sync", section: .actions, title: "Sincronizar", subtitle: "Actualizar desde SAIA con archivos",
                        keywords: "actualizar descargar saia moodle", symbol: "arrow.triangle.2.circlepath", action: .sync(includeFiles: true)),
            PaletteItem(id: "action:sync-nofiles", section: .actions, title: "Sincronizar sin archivos",
                        subtitle: "Solo actividades y fechas", keywords: "actualizar rápido saia", symbol: "arrow.triangle.2.circlepath",
                        action: .sync(includeFiles: false)),
            PaletteItem(id: "action:settings", section: .actions, title: "Ajustes", subtitle: "Preferencias de la aplicación",
                        keywords: "preferencias configuración", symbol: "gearshape", action: .openSettings),
            PaletteItem(id: "action:onboarding", section: .actions, title: "Asistente de configuración",
                        subtitle: "Volver a ejecutar la configuración inicial", keywords: "ayuda wizard", symbol: "wand.and.stars",
                        action: .openOnboarding),
        ]
        for other in AgentProviderID.allCases where other != provider {
            result.append(PaletteItem(
                id: "action:provider:\(other.rawValue)", section: .actions, title: "Cambiar agente a \(other.displayName)",
                subtitle: "Proveedor de las conversaciones nuevas", keywords: "agente proveedor modelo",
                symbol: "arrow.left.arrow.right", action: .setProvider(other)))
        }
        return result
    }

    /// Recipe rows for a query: "Ejecutar <receta> en <actividad o materia>". Empty unless the query matches a recipe.
    static func recipeItems(
        query: String, recipes: [Recipe] = RecipeCatalog.all, activities: [Activity], courses: [Course],
        contextActivity: Activity?, contextCourse: Course?, stateOf: (Activity) -> ActivityState, now: Date
    ) -> [PaletteItem] {
        let tokens = PaletteMatcher.tokens(query)
        guard !tokens.isEmpty else { return [] }
        var result: [PaletteItem] = []
        for recipe in recipes {
            let haystack = PaletteMatcher.fold("ejecutar receta \(recipe.title) \(recipe.subtitle)")
            let (matched, leftover) = partition(tokens, in: haystack)
            guard !matched.isEmpty else { continue }
            switch recipe.applicability {
            case .activity:
                for activity in activityTargets(recipe, leftover: leftover, activities: activities,
                                                context: contextActivity, stateOf: stateOf, now: now) {
                    result.append(item(recipe, scopeName: activity.name, folder: activity.folder, isCourse: false,
                                       courseFolder: activity.courseFolderName))
                }
            case .course:
                for course in courseTargets(leftover: leftover, courses: courses, context: contextCourse) {
                    result.append(item(recipe, scopeName: course.name, folder: course.folderName, isCourse: true,
                                       courseFolder: course.folderName))
                }
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func item(_ recipe: Recipe, scopeName: String, folder: String, isCourse: Bool, courseFolder: String) -> PaletteItem {
        PaletteItem(id: "recipe:\(recipe.id):\(folder)", section: .recipes, title: "Ejecutar \(recipe.title) en \(scopeName)",
                    subtitle: recipe.subtitle, symbol: recipe.symbol,
                    action: .runRecipe(recipeID: recipe.id, scopeFolder: folder, isCourse: isCourse), courseFolder: courseFolder)
    }

    private static func partition(_ tokens: [[Character]], in haystack: [Character]) -> (matched: [[Character]], leftover: [[Character]]) {
        var matched: [[Character]] = [], leftover: [[Character]] = []
        for token in tokens {
            if contains(haystack, token) { matched.append(token) } else { leftover.append(token) }
        }
        return (matched, leftover)
    }

    private static func contains(_ hay: [Character], _ needle: [Character]) -> Bool {
        guard !needle.isEmpty, hay.count >= needle.count else { return false }
        return (0...(hay.count - needle.count)).contains { hay[$0..<($0 + needle.count)].elementsEqual(needle) }
    }

    private static func activityTargets(_ recipe: Recipe, leftover: [[Character]], activities: [Activity], context: Activity?,
                                        stateOf: (Activity) -> ActivityState, now: Date) -> [Activity] {
        let applicable = activities.filter { recipe.applies(to: .activity($0)) }
        if leftover.isEmpty {
            if let context, recipe.applies(to: .activity(context)) { return [context] }
            let open = applicable.filter { stateOf($0) != .submitted && ($0.due.map { $0 >= now } ?? false) }
            let nearest = open.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            return nearest.map { [$0] } ?? []
        }
        let matching = applicable.filter { a in
            let text = PaletteMatcher.fold("\(a.name) \(a.courseName)")
            return leftover.allSatisfy { contains(text, $0) }
        }
        return Array(matching.prefix(2))
    }

    private static func courseTargets(leftover: [[Character]], courses: [Course], context: Course?) -> [Course] {
        if leftover.isEmpty { return context.map { [$0] } ?? [] }
        let matching = courses.filter { c in
            let text = PaletteMatcher.fold(c.name)
            return leftover.allSatisfy { contains(text, $0) }
        }
        return Array(matching.prefix(2))
    }

    private static func fileSymbol(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "md", "txt": "doc.plaintext"
        case "png", "jpg", "jpeg", "gif": "photo"
        default: "doc"
        }
    }
}
