import Testing
import Foundation
@testable import Catedra

struct ScriptLinkTests {
    private let root = URL(fileURLWithPath: "/Users/x/UFT/7th semestre")

    @Test func parsesStartWithAbsoluteOrRelativeFile() {
        let absolute = URL(string: "catedra://guion/activar?archivo=/Users/x/UFT/7th%20semestre/Redes/guiones/demo.md")!
        #expect(ScriptLink.parse(absolute, workspace: root) == .start(root.appending(path: "Redes/guiones/demo.md")))
        let relative = URL(string: "catedra://guion/activar?archivo=Redes/guiones/demo.md")!
        #expect(ScriptLink.parse(relative, workspace: root) == .start(root.appending(path: "Redes/guiones/demo.md")))
    }

    @Test func rejectsFilesOutsideTheWorkspaceOrNotMarkdown() {
        let outside = URL(string: "catedra://guion/activar?archivo=/etc/passwd.md")!
        #expect(ScriptLink.parse(outside, workspace: root) == .invalid("El guion debe estar dentro de la carpeta de Cátedra."))
        let escape = URL(string: "catedra://guion/activar?archivo=../../secret.md")!
        #expect(ScriptLink.parse(escape, workspace: root) == .invalid("El guion debe estar dentro de la carpeta de Cátedra."))
        let notMarkdown = URL(string: "catedra://guion/activar?archivo=Redes/guion.txt")!
        #expect(ScriptLink.parse(notMarkdown, workspace: root) == .invalid("El guion debe ser un archivo .md."))
        let missing = URL(string: "catedra://guion/activar")!
        #expect(ScriptLink.parse(missing, workspace: root) == .invalid("Falta el parámetro «archivo» del guion."))
    }

    @Test func parsesStopAndIgnoresOtherLinks() {
        #expect(ScriptLink.parse(URL(string: "catedra://guion/cerrar")!, workspace: root) == .stop)
        #expect(ScriptLink.parse(URL(string: "catedra://review")!, workspace: root) == nil)
        #expect(ScriptLink.parse(URL(string: "https://guion/activar")!, workspace: root) == nil)
    }

    @Test func buildsTheLinkTheAgentRuns() {
        let file = root.appending(path: "Redes/guiones/demo final.md")
        let url = ScriptLink.startURL(for: file)
        #expect(ScriptLink.parse(url, workspace: root) == .start(file))
    }
}
