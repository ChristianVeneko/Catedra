import Testing
import Foundation
@testable import Catedra

struct BinaryLocatorTests {
    func locator(_ provider: AgentProviderID = .claude, existing: Set<String>, shell: String? = nil) -> BinaryLocator {
        BinaryLocator(provider: provider, home: "/Users/u", isExecutable: { existing.contains($0) }, shellLookup: { shell })
    }

    @Test func prefersOverrideWhenExecutable() {
        let l = locator(existing: ["/custom/claude", "/Users/u/.local/bin/claude"])
        #expect(l.locate(override: "/custom/claude") == "/custom/claude")
    }

    @Test func ignoresInvalidOverride() {
        let l = locator(existing: ["/Users/u/.local/bin/claude"])
        #expect(l.locate(override: "/missing/claude") == "/Users/u/.local/bin/claude")
    }

    @Test func claudeChecksKnownLocationsInOrder() {
        #expect(locator(existing: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]).locate() == "/opt/homebrew/bin/claude")
        #expect(locator(existing: ["/usr/local/bin/claude"]).locate() == "/usr/local/bin/claude")
    }

    @Test func antigravityUsesAgyBinaryName() {
        #expect(locator(.antigravity, existing: ["/Users/u/.local/bin/agy"]).locate() == "/Users/u/.local/bin/agy")
        #expect(locator(.antigravity, existing: ["/Users/u/.local/bin/claude"]).locate() == nil)
    }

    @Test func openCodeChecksBunAndItsOwnInstallDirFirst() {
        let all: Set<String> = ["/Users/u/.bun/bin/opencode", "/Users/u/.opencode/bin/opencode", "/opt/homebrew/bin/opencode"]
        #expect(locator(.opencode, existing: all).locate() == "/Users/u/.bun/bin/opencode")
        #expect(locator(.opencode, existing: ["/Users/u/.opencode/bin/opencode", "/opt/homebrew/bin/opencode"]).locate() == "/Users/u/.opencode/bin/opencode")
        #expect(locator(.opencode, existing: ["/usr/local/bin/opencode"]).locate() == "/usr/local/bin/opencode")
    }

    @Test func fallsBackToLoginShell() {
        #expect(locator(existing: ["/weird/claude"], shell: "/weird/claude").locate() == "/weird/claude")
    }

    @Test func returnsNilWhenNothingFound() {
        #expect(locator(existing: [], shell: "/nope/claude").locate() == nil)
        #expect(locator(.opencode, existing: [], shell: nil).locate() == nil)
    }

    @Test func mergedPathKeepsOrderAndDeduplicates() {
        let path = LoginShellEnvironment.mergedPath(shellPath: "/a:/b:/a", currentPath: "/b:/c", home: "/h")
        let parts = path.split(separator: ":").map(String.init)
        #expect(Array(parts.prefix(3)) == ["/a", "/b", "/c"])
        #expect(Set(parts).count == parts.count)
        #expect(parts.contains("/h/.local/bin"))
        #expect(parts.contains("/opt/homebrew/bin"))
    }
}
