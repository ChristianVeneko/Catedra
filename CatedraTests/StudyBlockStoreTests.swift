import Testing
import Foundation
@testable import Catedra

struct StudyBlockStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("catedra-\(UUID().uuidString)/study-blocks.json")
    }

    @Test func roundTrip() throws {
        let store = JSONStudyBlockStore(file: tempFile())
        let b = StudyBlock(title: "Repaso", start: Date(timeIntervalSince1970: 1_000_000), end: Date(timeIntervalSince1970: 1_003_600),
                           activityID: "01 - X/T", courseFolder: "01 - X", notes: "cap 3", done: true)
        try store.save([b])
        #expect(store.load() == [b])
    }

    @Test func missingFileIsEmpty() {
        #expect(JSONStudyBlockStore(file: tempFile()).load().isEmpty)
    }

    @Test func malformedFileIsEmpty() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(JSONStudyBlockStore(file: file).load().isEmpty)
    }

    @Test func decodingIsTolerant() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        [{"start":"2026-10-06T14:00:00Z"},
         {"id":"\(UUID().uuidString)","title":"Ok","start":"2026-10-06T14:00:00Z","end":"2026-10-06T15:30:00Z","extra":1},
         {"title":"sin fecha"},
         42]
        """
        try Data(json.utf8).write(to: file)
        let blocks = JSONStudyBlockStore(file: file).load()
        #expect(blocks.count == 2)
        #expect(blocks[0].title == "Bloque de estudio")
        #expect(blocks[0].end.timeIntervalSince(blocks[0].start) == 3600)
        #expect(blocks[0].done == false && blocks[0].notes.isEmpty && blocks[0].activityID == nil)
        #expect(blocks[1].title == "Ok" && blocks[1].end.timeIntervalSince(blocks[1].start) == 5400)
    }
}
