import Testing
import Foundation
@testable import Catedra

struct RecipeCatalogTests {
    let course = Course(folderName: "08 - Teoria de Control II")!
    let due = Date(timeIntervalSince1970: 1_800_000_000)

    func scope(_ kind: ActivityKind) -> AgentScope {
        .activity(makeActivity(kind: kind, name: "Parcial 2", due: due))
    }

    func ids(_ kind: ActivityKind) -> [String] { RecipeCatalog.recipes(for: scope(kind)).map(\.id) }

    @Test func tareaRecipes() {
        #expect(ids(.tarea) == ["draft-docx", "review-draft", "work-plan"])
    }

    @Test func examAndQuizRecipesArePreparationOnly() {
        let prep = ["study-guide", "practice-exam", "key-concepts"]
        #expect(ids(.examen) == prep)
        #expect(ids(.cuestionario) == prep)
    }

    @Test func otherKindsOnlyGetFreeForm() {
        #expect(ids(.other("Foro")).isEmpty)
    }

    @Test func courseRecipes() {
        let ids = RecipeCatalog.recipes(for: .course(course)).map(\.id)
        #expect(ids == ["course-summary", "study-plan", "organize-notes", "flashcards", "quiz"])
    }

    @Test func noExamRecipeAsksToAnswerALiveExam() {
        let forbidden = ["resuelve el", "responde el", "contesta el", "resuelve las preguntas", "responde las preguntas",
                         "contesta las preguntas", "resuelve este", "responde este", "completa el examen", "completa el cuestionario"]
        for kind in [ActivityKind.examen, .cuestionario] {
            for recipe in RecipeCatalog.recipes(for: scope(kind)) {
                let text = RecipeCatalog.render(recipe, scope: scope(kind), activities: [], formatDate: { _ in "x" }).lowercased()
                for phrase in forbidden { #expect(!text.contains(phrase), "\(recipe.id) contains «\(phrase)»") }
                #expect(text.contains("no resuelvas"), "\(recipe.id) must state the preparation-only rule")
            }
        }
    }

    @Test func rendersPlaceholders() {
        let s = scope(.tarea)
        for recipe in RecipeCatalog.recipes(for: s) {
            let text = RecipeCatalog.render(recipe, scope: s, activities: [], formatDate: { _ in "FECHA" })
            #expect(!text.contains("{{"), "\(recipe.id) left a placeholder")
            #expect(text.contains("Parcial 2"))
            #expect(text.contains("FECHA"))
        }
    }

    @Test func rendersActivityListForCourse() {
        let a = makeActivity(name: "Quiz 1", due: due, folder: "08 - Teoria de Control II/actividades/Cuestionario - Quiz 1")
        let b = makeActivity(name: "Sin fecha", due: nil, folder: "08 - Teoria de Control II/actividades/Tarea - Sin fecha")
        let recipe = RecipeCatalog.recipes(for: .course(course)).first { $0.id == "study-plan" }!
        let text = RecipeCatalog.render(recipe, scope: .course(course), activities: [a, b], formatDate: { _ in "FECHA" })
        #expect(text.contains("Quiz 1"))
        #expect(text.contains("FECHA"))
        #expect(text.contains("Sin fecha"))
        #expect(text.contains("Teoria de Control II"))
        #expect(!text.contains("{{"))
    }

    @Test func recipeLookupById() {
        #expect(RecipeCatalog.recipe(id: "work-plan")?.id == "work-plan")
        #expect(RecipeCatalog.recipe(id: "nope") == nil)
    }
}
