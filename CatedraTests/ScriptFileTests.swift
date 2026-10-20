import Testing
import Foundation
@testable import Catedra

struct ScriptFileTests {
    @Test func markdownInAGuionesFolderIsAScript() {
        #expect(ScriptFile.isScript(path: "/w/Redes/apuntes/guiones/demo.md", head: nil))
        #expect(ScriptFile.isScript(path: "/w/Redes/apuntes/Guiones/Demo.MD", head: nil))
        #expect(!ScriptFile.isScript(path: "/w/Redes/apuntes/guiones/notas.txt", head: nil))
        #expect(!ScriptFile.isScript(path: "/w/Redes/apuntes/resumen.md", head: "# Resumen\n\nTexto."))
    }

    @Test func frontmatterTipoGuionMarksAScriptAnywhere() {
        #expect(ScriptFile.isScript(path: "/w/Redes/entrega/presentacion.md", head: "---\ntitulo: Demo\ntipo: guion\n---\nHola."))
        #expect(ScriptFile.isScript(path: "/w/x.md", head: "---\nTipo: \"Guion\"\n---\n"))
        #expect(!ScriptFile.isScript(path: "/w/x.md", head: "---\ntipo: apuntes\n---\n"))
        #expect(!ScriptFile.isScript(path: "/w/x.md", head: "Texto con tipo: guion en el cuerpo."))
    }

    @Test func readsTheFileHead() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "ScriptFileTests-\(UUID().uuidString).md")
        try "---\ntipo: guion\n---\nHola.".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(ScriptFile.isScript(file))
        #expect(!ScriptFile.isScript(URL(fileURLWithPath: "/nonexistent/x.md")))
    }
}
