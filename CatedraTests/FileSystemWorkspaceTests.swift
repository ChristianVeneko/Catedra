import Testing
import Foundation
@testable import Catedra

struct FileSystemWorkspaceTests {
    func makeWorkspace() throws -> URL {
        let root = try makeTempDirectory()
        let fm = FileManager.default
        func dir(_ p: String) throws { try fm.createDirectory(at: root.appendingPathComponent(p), withIntermediateDirectories: true) }
        func file(_ p: String, _ s: String = "x") throws { try s.write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8) }
        try dir("_sistema/data")
        try dir("08 - Teoria de Control II/actividades/Examen - Parcial No. 1/preparacion")
        try dir("08 - Teoria de Control II/actividades/Examen - Parcial No. 1/material")
        try dir("08 - Teoria de Control II/actividades/Tarea - Otra/entrega")
        try dir("08 - Teoria de Control II/contenidos/01 - Unidad")
        try dir("08 - Teoria de Control II/foros")
        try file("08 - Teoria de Control II/actividades/Examen - Parcial No. 1/preparacion/resumen.md")
        try file("08 - Teoria de Control II/actividades/Examen - Parcial No. 1/preparacion/.DS_Store")
        try file("08 - Teoria de Control II/actividades/Examen - Parcial No. 1/material/guia.pdf")
        try file("08 - Teoria de Control II/contenidos/01 - Unidad/_notas.md")
        try file("08 - Teoria de Control II/foros/Foro 1.md")
        try file("08 - Teoria de Control II/README.md")
        try dir("02 - Diseno de Software")
        let json = """
        [{"course":"Teoria de Control II","type":"Examen","name":"Parcial No. 1","due":1792382340,"status":"Pendiente","grade":"","url":"https://x/1","folder":"08 - Teoria de Control II/actividades/Examen - Parcial No. 1"},
         {"course":"Teoria de Control II","type":"Tarea","name":"Otra","due":0,"status":"Pendiente","grade":"","url":"https://x/2","folder":"08 - Teoria de Control II/actividades/Tarea - Otra"}]
        """
        try file("_sistema/data/activities.json", json)
        return root
    }

    @Test func loadsCoursesSortedByNumberAndSkipsSystemFolder() throws {
        let snap = try FileSystemWorkspace().loadSnapshot(root: makeWorkspace())
        #expect(snap.courses.map(\.number) == [2, 8])
        #expect(snap.courses.map(\.name) == ["Diseno de Software", "Teoria de Control II"])
        #expect(snap.courses[1].folderName == "08 - Teoria de Control II")
    }

    @Test func detectsUserWorkIgnoringHiddenFilesAndMaterial() throws {
        let snap = try FileSystemWorkspace().loadSnapshot(root: makeWorkspace())
        let exam = try #require(snap.activities.first { $0.name == "Parcial No. 1" })
        let other = try #require(snap.activities.first { $0.name == "Otra" })
        #expect(snap.activitiesWithUserWork.contains(exam.id))
        #expect(!snap.activitiesWithUserWork.contains(other.id))
    }

    @Test func listsActivityFilesPerFolder() throws {
        let root = try makeWorkspace()
        let ws = FileSystemWorkspace()
        let snap = try ws.loadSnapshot(root: root)
        let exam = try #require(snap.activities.first { $0.name == "Parcial No. 1" })
        let files = ws.files(root: root, activity: exam)
        #expect(files.material.map(\.lastPathComponent) == ["guia.pdf"])
        #expect(files.preparacion.map(\.lastPathComponent) == ["resumen.md"])
        #expect(files.entrega.isEmpty)
        #expect(files.apuntes.isEmpty)
    }

    @Test func buildsContentTreeAndForums() throws {
        let root = try makeWorkspace()
        let ws = FileSystemWorkspace()
        let course = try #require(ws.loadSnapshot(root: root).courses.last)
        let tree = ws.contentTree(root: root, course: course)
        #expect(tree.count == 1)
        #expect(tree[0].name == "01 - Unidad")
        #expect(tree[0].children?.map(\.name) == ["_notas.md"])
        #expect(ws.forums(root: root, course: course).map(\.name) == ["Foro 1.md"])
    }

    @Test func missingActivitiesJSONYieldsEmptyActivities() throws {
        let root = try makeTempDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("01 - A"), withIntermediateDirectories: true)
        let snap = try FileSystemWorkspace().loadSnapshot(root: root)
        #expect(snap.activities.isEmpty)
        #expect(snap.courses.count == 1)
    }

    @Test func contentTreeHidesGeneratedImageFolders() throws {
        let root = try makeWorkspace()
        let fm = FileManager.default
        let unit = root.appendingPathComponent("08 - Teoria de Control II/contenidos/01 - Unidad")
        try fm.createDirectory(at: unit.appendingPathComponent("_imagenes"), withIntermediateDirectories: true)
        try "x".write(to: unit.appendingPathComponent("_imagenes/blob.jpg"), atomically: true, encoding: .utf8)
        let course = try #require(Course(folderName: "08 - Teoria de Control II"))
        let tree = FileSystemWorkspace().contentTree(root: root, course: course)
        let names = tree.first?.children?.map(\.name) ?? []
        #expect(names == ["_notas.md"])
    }
}
