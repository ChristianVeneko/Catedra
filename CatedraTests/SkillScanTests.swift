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

    // MARK: - Other providers

    func tree(_ files: [String: String]) throws -> URL {
        let root = try makeTempDirectory()
        for (rel, text) in files {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("home/ws/course"), withIntermediateDirectories: true)
        return root
    }

    @Test func antigravityScansAgentsSkillsInProjectAncestorsAndUserFolders() throws {
        let root = try tree([
            "home/.agents/skills/global/SKILL.md": "---\nname: global\ndescription: Global\n---\n",
            "home/.gemini/config/skills/cfg/SKILL.md": "---\ndescription: De config\n---\n",
            "home/ws/.agents/skills/proj/SKILL.md": "---\nname: proj\ndescription: Proyecto\n---\n",
            "home/ws/.claude/skills/ignored/SKILL.md": "---\nname: ignored\n---\n",
        ])
        let scanner = LocalSlashCommandScanner(home: root.appendingPathComponent("home"), layout: .antigravity)
        let found = scanner.scan(folder: root.appendingPathComponent("home/ws/course"))
        #expect(found.map(\.name) == ["cfg", "global", "proj"])
        #expect(found.first { $0.name == "global" }?.description == "Global")
    }

    @Test func openCodeScansMarkdownCommandsWithPathNames() throws {
        let root = try tree([
            "home/.config/opencode/commands/test.md": "---\ndescription: Corre pruebas\n---\nRun tests $ARGUMENTS",
            "home/ws/.opencode/command/git/commit.md": "---\ndescription: Commit\n---\nhi",
            "home/ws/.opencode/commands/plain.md": "sin frontmatter",
            "home/ws/.opencode/commands/notes.txt": "no",
        ])
        let scanner = LocalSlashCommandScanner(home: root.appendingPathComponent("home"), layout: .opencode)
        let found = scanner.scan(folder: root.appendingPathComponent("home/ws/course"))
        #expect(found.map(\.name) == ["git/commit", "plain", "test"])
        #expect(found.first { $0.name == "test" }?.description == "Corre pruebas")
        #expect(found.first { $0.name == "plain" }?.description == "")
    }

    @Test func layoutIsChosenPerProvider() {
        #expect(CommandLayout.layout(for: .claude).projectFolders == [".claude"])
        #expect(CommandLayout.layout(for: .antigravity).projectFolders.first == ".agents")
        #expect(CommandLayout.layout(for: .opencode).commandFolders == ["command", "commands"])
    }
}
