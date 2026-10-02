import Foundation
@testable import Catedra

func makeActivity(
    course: String = "Teoria de Control II",
    kind: ActivityKind = .tarea,
    name: String = "Actividad",
    due: Date? = nil,
    status: String = "Pendiente",
    grade: String = "",
    url: String = "https://saia.uft.edu.ve/mod/assign/view.php?id=1",
    folder: String = "08 - Teoria de Control II/actividades/Tarea - Actividad"
) -> Activity {
    Activity(courseName: course, kind: kind, name: name, due: due, rawStatus: status, grade: grade,
             url: URL(string: url), folder: folder)
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("catedra-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
