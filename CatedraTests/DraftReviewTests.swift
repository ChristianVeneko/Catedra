import Testing
import Foundation
@testable import Catedra

struct DraftReviewTests {
    func parse(_ json: String) throws -> DraftReview { try DraftReviewParser.parse(Data(json.utf8)) }

    @Test func parsesFullDocument() throws {
        let review = try parse("""
        {"generatedAt":"2026-10-05T14:30:00Z","summary":"Falta la portada.","requirements":[
          {"id":"r1","requirement":"Incluir portada","status":"falta","evidence":"No hay portada","suggestion":"Agregar portada","source":"normas-uft"},
          {"id":"r2","requirement":"Describir el circuito","status":"cumple","evidence":"Sección 2","source":"enunciado"},
          {"id":"r3","requirement":"Citas","status":"parcial","evidence":"Dos sin año","source":"rubrica"}]}
        """)
        #expect(review.summary == "Falta la portada.")
        #expect(review.generatedAt == ISO8601DateFormatter().date(from: "2026-10-05T14:30:00Z"))
        #expect(review.requirements.count == 3)
        #expect(review.requirements[0].status == .falta)
        #expect(review.requirements[0].source == .normasUFT)
        #expect(review.requirements[0].suggestion == "Agregar portada")
        #expect(review.requirements[1].suggestion == nil)
        #expect(review.requirements[2].source == .rubrica)
    }

    @Test func countsByStatus() throws {
        let review = try parse("""
        {"requirements":[
          {"requirement":"a","status":"cumple"},{"requirement":"b","status":"cumple"},
          {"requirement":"c","status":"parcial"},{"requirement":"d","status":"falta"},{"requirement":"e","status":"???"}]}
        """)
        #expect(review.counts == ReviewCounts(cumple: 2, parcial: 1, falta: 1, unknown: 1))
        #expect(review.counts.total == 5)
    }

    @Test func unknownStatusAndSourceAreTolerated() throws {
        let review = try parse(#"{"requirements":[{"requirement":"x","status":"quizá","source":"otro"}]}"#)
        #expect(review.requirements[0].status == .unknown)
        #expect(review.requirements[0].source == .unknown)
    }

    @Test func statusIsCaseAndWhitespaceInsensitive() throws {
        let review = try parse(#"{"requirements":[{"requirement":"x","status":" Cumple "}]}"#)
        #expect(review.requirements[0].status == .cumple)
    }

    @Test func missingFieldsAreTolerated() throws {
        let review = try parse(#"{"requirements":[{"requirement":"x"},{"requirement":"y","evidence":null,"suggestion":"  "}]}"#)
        #expect(review.generatedAt == nil)
        #expect(review.summary == "")
        #expect(review.requirements.map(\.id) == ["req-1", "req-2"])
        #expect(review.requirements[0].status == .unknown)
        #expect(review.requirements[0].evidence == "")
        #expect(review.requirements[1].suggestion == nil)
    }

    @Test func entriesWithoutRequirementTextAreSkipped() throws {
        let review = try parse(#"{"requirements":[{"status":"cumple"},"basura",{"requirement":"ok","status":"falta"}]}"#)
        #expect(review.requirements.map(\.requirement) == ["ok"])
    }

    @Test func missingRequirementsListGivesEmptyReview() throws {
        let review = try parse(#"{"summary":"Nada que revisar"}"#)
        #expect(review.requirements.isEmpty)
        #expect(review.counts.total == 0)
    }

    @Test func fractionalSecondsAndDateOnlyAreAccepted() throws {
        let a = try parse(#"{"generatedAt":"2026-10-05T14:30:00.123Z","requirements":[]}"#)
        let b = try parse(#"{"generatedAt":"2026-10-05","requirements":[]}"#)
        #expect(a.generatedAt != nil)
        #expect(b.generatedAt != nil)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: DraftReviewError.self) { try parse("{no es json") }
        #expect(throws: DraftReviewError.self) { try parse("[1,2]") }
        #expect(throws: DraftReviewError.self) { try parse("") }
    }

    @Test func loadStateReflectsFileContents() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("apuntes"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(DraftReviewFile.load(in: dir) == .missing)

        let url = dir.appendingPathComponent(DraftReviewFile.relativePath)
        try Data(#"{"requirements":[{"requirement":"x","status":"cumple"}]}"#.utf8).write(to: url)
        guard case .loaded(let review) = DraftReviewFile.load(in: dir) else { Issue.record("expected loaded"); return }
        #expect(review.counts.cumple == 1)

        try Data("roto".utf8).write(to: url)
        guard case .invalid = DraftReviewFile.load(in: dir) else { Issue.record("expected invalid"); return }
    }

    @Test func recipeIsTaskOnlyAndStaysEvaluationSafe() {
        let activity = makeActivity(kind: .tarea, name: "Informe 1", due: nil)
        let recipe = RecipeCatalog.recipes(for: .activity(activity)).first { $0.id == "review-draft" }
        #expect(recipe?.title == "Revisar entrega")
        #expect(RecipeCatalog.recipes(for: .activity(makeActivity(kind: .examen, name: "P", due: nil))).allSatisfy { $0.id != "review-draft" })
        let text = RecipeCatalog.render(recipe!, scope: .activity(activity), activities: [], formatDate: { _ in "x" })
        #expect(text.contains(DraftReviewFile.relativePath))
        #expect(text.contains("no reescribas"))
        #expect(text.contains("normas-uft"))
    }
}
