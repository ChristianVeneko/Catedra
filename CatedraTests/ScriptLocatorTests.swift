import Testing
import Foundation
@testable import Catedra

struct ScriptLocatorTests {
    private func makeFolder(_ files: [(String, TimeInterval)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ScriptLocatorTests-\(UUID().uuidString)")
        let folder = root.appending(path: ScriptLocator.relativeFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, age) in files {
            let url = folder.appending(path: name)
            try "Hola.".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.path)
        }
        return root
    }

    @Test func withoutANameReturnsTheNewestScript() throws {
        let root = try makeFolder([("viejo.md", 300), ("nuevo.md", 10), ("notas.txt", 1)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ScriptLocator.find(nil, in: root)?.lastPathComponent == "nuevo.md")
    }

    @Test func matchesNamesWithoutAccentsOrCase() throws {
        let root = try makeFolder([("Defensa de Tesis.md", 300), ("demo-app.md", 10)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ScriptLocator.find("defensa tesis", in: root)?.lastPathComponent == "Defensa de Tesis.md")
        #expect(ScriptLocator.find("DEMO", in: root)?.lastPathComponent == "demo-app.md")
        #expect(ScriptLocator.find("presupuesto", in: root) == nil)
    }

    @Test func matchesTheFileNameAsTyped() throws {
        let root = try makeFolder([("resumen-ensayo.md", 10), ("otro.md", 5)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ScriptLocator.find("resumen-ensayo", in: root)?.lastPathComponent == "resumen-ensayo.md")
        #expect(ScriptLocator.find("resumen-ensayo.md", in: root)?.lastPathComponent == "resumen-ensayo.md")
        #expect(ScriptLocator.find("resumen", in: root)?.lastPathComponent == "resumen-ensayo.md")
    }

    @Test func missingFolderFindsNothing() {
        #expect(ScriptLocator.find(nil, in: URL(fileURLWithPath: "/nonexistent")) == nil)
    }
}
