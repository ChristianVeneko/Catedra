import Testing
import Foundation
@testable import Catedra

struct ActivityJSONDecoderTests {
    static let json = """
    [
      {"course": "Teoria de Control II", "type": "Examen", "name": "Parcial No. 1", "due": 1792382340,
       "status": "Proximo (aun no abre)", "grade": "",
       "url": "https://saia.uft.edu.ve/mod/quiz/view.php?id=1532247",
       "folder": "08 - Teoria de Control II/actividades/Examen - Parcial No. 1"},
      {"course": "Diseno de Software", "type": "Tarea", "name": "Sin fecha", "due": 0,
       "status": "Pendiente", "grade": "", "url": "", "folder": "02 - Diseno de Software/actividades/Tarea - Sin fecha"},
      {"course": "X", "type": "Foro", "name": "Y", "due": 5, "status": "Pendiente", "grade": "10", "url": "https://a/b", "folder": "01 - X/actividades/Foro - Y"}
    ]
    """

    @Test func decodesRealShape() throws {
        let items = try ActivityJSONDecoder.decode(Data(Self.json.utf8))
        #expect(items.count == 3)
        #expect(items[0].kind == .examen)
        #expect(items[0].due == Date(timeIntervalSince1970: 1_792_382_340))
        #expect(items[0].url?.absoluteString == "https://saia.uft.edu.ve/mod/quiz/view.php?id=1532247")
        #expect(items[0].rawStatus == "Proximo (aun no abre)")
    }

    @Test func zeroDueMeansNoDate() throws {
        let items = try ActivityJSONDecoder.decode(Data(Self.json.utf8))
        #expect(items[1].due == nil)
        #expect(items[1].url == nil)
    }

    @Test func unknownTypeBecomesOther() throws {
        let items = try ActivityJSONDecoder.decode(Data(Self.json.utf8))
        #expect(items[2].kind == .other("Foro"))
        #expect(items[2].grade == "10")
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try ActivityJSONDecoder.decode(Data("{".utf8)) }
    }
}

struct ActivityJSONDecoderRichFieldsTests {
    @Test func decodesOptionalPhase4Fields() throws {
        let json = """
        [{"course":"X","type":"Tarea","name":"T","due":100,"status":"Calificada","grade":"8.50/10","url":"",
          "folder":"01 - X/actividades/Tarea - T","opens":50,"cutoff":200,"gradeRaw":8.5,"gradeMax":10,
          "feedback":"Bien","gradedAt":150,"cmid":77}]
        """
        let a = try #require(try ActivityJSONDecoder.decode(Data(json.utf8)).first)
        #expect(a.opens == Date(timeIntervalSince1970: 50))
        #expect(a.cutoff == Date(timeIntervalSince1970: 200))
        #expect(a.gradeRaw == 8.5)
        #expect(a.gradeMax == 10)
        #expect(a.feedback == "Bien")
        #expect(a.hasFeedback)
        #expect(a.gradedAt == Date(timeIntervalSince1970: 150))
        #expect(a.cmid == 77)
        #expect(a.grade == "8.50/10")
    }

    @Test func oldFilesWithoutNewFieldsStillDecode() throws {
        let a = try #require(try ActivityJSONDecoder.decode(Data(ActivityJSONDecoderTests.json.utf8)).first)
        #expect(a.opens == nil && a.cutoff == nil && a.gradeRaw == nil && a.gradeMax == nil)
        #expect(a.gradedAt == nil && a.cmid == nil)
        #expect(a.feedback.isEmpty && !a.hasFeedback)
    }

    @Test func zeroDatesMeanAbsent() throws {
        let json = #"[{"course":"X","type":"Tarea","name":"T","due":0,"folder":"f","opens":0,"cutoff":0}]"#
        let a = try #require(try ActivityJSONDecoder.decode(Data(json.utf8)).first)
        #expect(a.opens == nil && a.cutoff == nil)
    }

    /// Some teachers only set the cut-off date; it is then the real deadline.
    @Test func cutoffBecomesDeadlineWhenDueIsMissing() throws {
        let json = #"[{"course":"X","type":"Tarea","name":"T","due":0,"folder":"f","cutoff":200}]"#
        let a = try #require(try ActivityJSONDecoder.decode(Data(json.utf8)).first)
        #expect(a.due == Date(timeIntervalSince1970: 200))
        #expect(a.dueIsCutoff)
        #expect(ActivityState.derive(from: a, hasUserWork: false, now: Date(timeIntervalSince1970: 300)) == .overdue)
    }

    @Test func explicitDueIsKeptOverCutoff() throws {
        let json = #"[{"course":"X","type":"Tarea","name":"T","due":100,"folder":"f","cutoff":200}]"#
        let a = try #require(try ActivityJSONDecoder.decode(Data(json.utf8)).first)
        #expect(a.due == Date(timeIntervalSince1970: 100))
        #expect(!a.dueIsCutoff)
    }
}
