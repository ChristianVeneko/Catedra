import Testing
import Foundation
@testable import Catedra

struct WorkspaceSetupTests {
    // MARK: inspector

    @Test func emptyWritableFolderHasNoExistingWorkspace() throws {
        let dir = try makeTempDirectory()
        let result = WorkspaceInspector().inspect(dir)
        #expect(result.exists)
        #expect(result.isWritable)
        #expect(result.existingActivityCount == nil)
        #expect(!result.hasAgentInstructions)
        #expect(result.isEmpty)
    }

    @Test func detectsExistingWorkspaceAndCountsActivities() throws {
        let dir = try makeTempDirectory()
        let data = dir.appendingPathComponent("_sistema/data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data(#"[{"name":"a"},{"name":"b"},{"name":"c"}]"#.utf8).write(to: data.appendingPathComponent("activities.json"))
        let result = WorkspaceInspector().inspect(dir)
        #expect(result.existingActivityCount == 3)
        #expect(!result.isEmpty)
    }

    @Test func corruptActivitiesFileCountsAsNoWorkspace() throws {
        let dir = try makeTempDirectory()
        let data = dir.appendingPathComponent("_sistema/data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: data.appendingPathComponent("activities.json"))
        #expect(WorkspaceInspector().inspect(dir).existingActivityCount == nil)
    }

    @Test func detectsAgentInstructionFiles() throws {
        let dir = try makeTempDirectory()
        try Data("x".utf8).write(to: dir.appendingPathComponent("CLAUDE.md"))
        #expect(WorkspaceInspector().inspect(dir).hasAgentInstructions)
        let other = try makeTempDirectory()
        try Data("x".utf8).write(to: other.appendingPathComponent("AGENTS.md"))
        #expect(WorkspaceInspector().inspect(other).hasAgentInstructions)
    }

    @Test func missingFolderIsNotWritableButItsParentIsCreatable() throws {
        let parent = try makeTempDirectory()
        let child = parent.appendingPathComponent("Nueva", isDirectory: true)
        let result = WorkspaceInspector().inspect(child)
        #expect(!result.exists)
        #expect(result.isWritable) // can be created inside a writable parent
    }

    @Test func readOnlyFolderIsNotWritable() throws {
        let dir = try makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(!WorkspaceInspector().inspect(dir).isWritable)
    }

    // MARK: starter files

    @Test func starterTextDescribesLayoutAndRules() {
        let agents = StarterInstructions.agentsMarkdown
        for needle in ["entrega/", "preparacion/", "apuntes/", "enunciado.md", "_sistema", "overwritten", "Spanish", "contenidos/", "PENDIENTES.md"] {
            #expect(agents.contains(needle), "missing \(needle)")
        }
        #expect(StarterInstructions.claudeMarkdown == "@AGENTS.md\n")
    }

    @Test func writerCreatesBothFilesInAWorkspaceWithoutThem() throws {
        let dir = try makeTempDirectory()
        let created = try StarterFilesWriter().write(into: dir)
        #expect(Set(created) == ["AGENTS.md", "CLAUDE.md"])
        #expect(try String(contentsOf: dir.appendingPathComponent("CLAUDE.md"), encoding: .utf8) == "@AGENTS.md\n")
        #expect(try String(contentsOf: dir.appendingPathComponent("AGENTS.md"), encoding: .utf8) == StarterInstructions.agentsMarkdown)
    }

    @Test func writerNeverOverwritesExistingFiles() throws {
        let dir = try makeTempDirectory()
        try Data("mine".utf8).write(to: dir.appendingPathComponent("AGENTS.md"))
        let created = try StarterFilesWriter().write(into: dir)
        #expect(created == ["CLAUDE.md"])
        #expect(try String(contentsOf: dir.appendingPathComponent("AGENTS.md"), encoding: .utf8) == "mine")
    }

    @Test func writerCreatesTheFolderWhenMissing() throws {
        let dir = try makeTempDirectory().appendingPathComponent("Cátedra", isDirectory: true)
        _ = try StarterFilesWriter().write(into: dir)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("AGENTS.md").path))
    }
}
