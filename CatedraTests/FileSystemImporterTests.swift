import Testing
import Foundation
@testable import Catedra

struct FileSystemImporterTests {
    func setup() throws -> (root: URL, activity: URL, source: URL) {
        let root = try makeTempDirectory()
        let activity = root.appendingPathComponent("01 - Curso/actividades/Tarea - A", isDirectory: true)
        try FileManager.default.createDirectory(at: activity, withIntermediateDirectories: true)
        let srcDir = try makeTempDirectory()
        let source = srcDir.appendingPathComponent("informe.pdf")
        try Data("hola".utf8).write(to: source)
        return (root, activity, source)
    }

    @Test func copiesIntoTargetAndKeepsSource() throws {
        let (root, activity, source) = try setup()
        let importer = FileSystemImporter(workspaceRoot: root)
        let out = try importer.importFiles([source], into: .entrega, activityFolder: activity)
        #expect(out.count == 1)
        #expect(out[0].deletingLastPathComponent().lastPathComponent == "entrega")
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: out[0]) == Data("hola".utf8))
    }

    @Test func suffixesCollisions() throws {
        let (root, activity, source) = try setup()
        let importer = FileSystemImporter(workspaceRoot: root)
        _ = try importer.importFiles([source], into: .preparacion, activityFolder: activity)
        let second = try importer.importFiles([source], into: .preparacion, activityFolder: activity)
        let third = try importer.importFiles([source], into: .preparacion, activityFolder: activity)
        #expect(second[0].lastPathComponent == "informe (2).pdf")
        #expect(third[0].lastPathComponent == "informe (3).pdf")
    }

    @Test func collisionNamerHandlesNoExtension() {
        let taken: Set<String> = ["notas", "notas (2)"]
        #expect(CollisionNamer.uniqueName(for: "notas", isTaken: { taken.contains($0) }) == "notas (3)")
        #expect(CollisionNamer.uniqueName(for: "libre.txt", isTaken: { taken.contains($0) }) == "libre.txt")
    }

    @Test func refusesActivityOutsideWorkspace() throws {
        let (root, _, source) = try setup()
        let outside = try makeTempDirectory()
        let importer = FileSystemImporter(workspaceRoot: root)
        #expect(throws: ImportError.self) {
            try importer.importFiles([source], into: .apuntes, activityFolder: outside)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func refusesTraversalInActivityPath() throws {
        let (root, activity, source) = try setup()
        let sneaky = activity.appendingPathComponent("../../../../..")
        let importer = FileSystemImporter(workspaceRoot: root)
        #expect(throws: ImportError.self) {
            try importer.importFiles([source], into: .entrega, activityFolder: sneaky)
        }
    }

    @Test func refusesSymlinkedTargetEscapingWorkspace() throws {
        let (root, activity, source) = try setup()
        let outside = try makeTempDirectory()
        try FileManager.default.createSymbolicLink(at: activity.appendingPathComponent("entrega"), withDestinationURL: outside)
        let importer = FileSystemImporter(workspaceRoot: root)
        #expect(throws: ImportError.self) {
            try importer.importFiles([source], into: .entrega, activityFolder: activity)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
