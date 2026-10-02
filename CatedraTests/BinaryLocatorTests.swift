import Testing
import Foundation
@testable import Catedra

struct ClaudeLocatorTests {
    func locator(existing: Set<String>, shell: String? = nil) -> ClaudeLocator {
        ClaudeLocator(home: "/Users/u", isExecutable: { existing.contains($0) }, shellLookup: { shell })
    }

    @Test func prefersOverrideWhenExecutable() {
        let l = locator(existing: ["/custom/claude", "/Users/u/.local/bin/claude"])
        #expect(l.locate(override: "/custom/claude") == "/custom/claude")
    }

    @Test func ignoresInvalidOverride() {
        let l = locator(existing: ["/Users/u/.local/bin/claude"])
        #expect(l.locate(override: "/missing/claude") == "/Users/u/.local/bin/claude")
    }

    @Test func checksKnownLocationsInOrder() {
        #expect(locator(existing: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]).locate() == "/opt/homebrew/bin/claude")
        #expect(locator(existing: ["/usr/local/bin/claude"]).locate() == "/usr/local/bin/claude")
    }

    @Test func fallsBackToLoginShell() {
        #expect(locator(existing: ["/weird/claude"], shell: "/weird/claude").locate() == "/weird/claude")
    }

    @Test func returnsNilWhenNothingFound() {
        #expect(locator(existing: [], shell: "/nope/claude").locate() == nil)
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
