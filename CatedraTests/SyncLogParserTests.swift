import Testing
@testable import Catedra

struct SyncLogParserTests {
    @Test func parsesCourseProgress() {
        #expect(SyncLogParser.parse("> 08 - Teoria de Control II", isError: false) == .course("08 - Teoria de Control II"))
    }
    @Test func parsesDone() {
        #expect(SyncLogParser.parse("Done: 22 activities, dashboard at /x/PENDIENTES.md", isError: false) == .done(activities: 22))
    }
    @Test func parsesLoginFailure() {
        let e = SyncLogParser.parse("Login failed: invalidlogin", isError: true)
        #expect(e == .loginFailed("invalidlogin"))
    }
    @Test func parsesStderrWarnings() {
        #expect(SyncLogParser.parse("  ! download failed a.pdf: boom", isError: true) == .warning("download failed a.pdf: boom"))
    }
    @Test func otherLinesAreInfo() {
        #expect(SyncLogParser.parse("  files: 3", isError: false) == .info("files: 3"))
    }
    @Test func blankLineIsIgnored() {
        #expect(SyncLogParser.parse("   ", isError: false) == .ignored)
    }
}
