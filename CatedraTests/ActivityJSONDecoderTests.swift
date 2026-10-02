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
