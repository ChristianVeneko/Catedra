import Testing
import Foundation
@testable import Catedra

struct LibprocSamplerTests {
    @Test func sampleOfOwnProcessHasMemory() throws {
        let snaps = LibprocSampler().snapshot(tree: getpid())
        let me = try #require(snaps.first { $0.pid == getpid() })
        #expect(me.rssBytes > 0)
        #expect(me.cpuSeconds > 0)
    }

    @Test func includesDescendants() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 5 & wait"]
        try p.run()
        defer { p.terminate() }
        var count = 0
        for _ in 0..<40 {
            count = LibprocSampler().snapshot(tree: p.processIdentifier).count
            if count >= 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(count >= 2)
    }

    @Test func unknownPIDYieldsNothing() {
        #expect(LibprocSampler().snapshot(tree: 999_999).isEmpty)
    }
}
