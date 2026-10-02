import Testing
import Foundation
@testable import Catedra

struct SkillScanTests {
    @Test func parsesFrontmatterFields() {
        let text = """
        ---
        name: normas-uft
        description: "Skill para elaborar trabajos"
        argument-hint: [name]
        ---
        # Cuerpo
        """
        let meta = SkillFrontmatter.parse(text)
        #expect(meta.name == "normas-uft")
        #expect(meta.description == "Skill para elaborar trabajos")
        #expect(meta.argumentHint == "[name]")
    }

    @Test func parsesFoldedAndLiteralBlocks() {
        let text = "---\nname: x\ndescription: >\n  primera línea\n  segunda línea\nother: 1\n---\nbody"
        #expect(SkillFrontmatter.parse(text).description == "primera línea segunda línea")
    }

    @Test func missingFrontmatterYieldsNothing() {
        let meta = SkillFrontmatter.parse("# solo markdown")
        #expect(meta.name == nil && meta.description == nil)
    }

    @Test func scansSkillsAndCommandsAndAncestors() throws {
        let root = try makeTempDirectory()
        let home = root.appendingPathComponent("home")
        let work = root.appendingPathComponent("home/ws/course/act")
        let fm = FileManager.default
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        func write(_ rel: String, _ text: String) throws {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("home/.claude/skills/uno/SKILL.md", "---\nname: uno\ndescription: Primera\n---\n")
        try write("home/.claude/skills/sin-nombre/SKILL.md", "---\ndescription: Usa carpeta\n---\n")
        try write("home/.claude/commands/cmd.md", "---\ndescription: Un comando\n---\nhola")
        try write("home/ws/.claude/skills/local/SKILL.md", "---\nname: local\ndescription: Del proyecto\n---\n")
        try write("home/ws/.claude/skills/not-a-skill/readme.md", "x")

        let scanner = LocalSlashCommandScanner(home: home)
        let commands = scanner.scan(folder: work)
        let names = commands.map(\.name).sorted()
        #expect(names == ["cmd", "local", "sin-nombre", "uno"])
        #expect(commands.allSatisfy { $0.kind == .skill })
        #expect(commands.first { $0.name == "uno" }?.description == "Primera")
    }
}
