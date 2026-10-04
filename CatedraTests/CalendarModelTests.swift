import Testing
import Foundation
@testable import Catedra

final class MemoryStudyStore: StudyBlockStoring, @unchecked Sendable {
    var blocks: [StudyBlock] = []
    func load() -> [StudyBlock] { blocks }
    func save(_ blocks: [StudyBlock]) throws { self.blocks = blocks }
}

@MainActor
struct CalendarModelTests {
    typealias F = CalendarFixtures

    func model(_ store: MemoryStudyStore = MemoryStudyStore()) -> CalendarModel {
        CalendarModel(store: store, calendar: F.cal, now: F.date(8, 10)) { FakeCalendarStore() }
    }

    @Test func saveEditToggleDeletePersist() {
        let store = MemoryStudyStore()
        let m = model(store)
        let block = StudyBlock(title: " ", start: F.date(9, 9), end: F.date(9, 8))
        m.save(block)
        #expect(store.blocks.count == 1 && store.blocks[0].title == StudyBlock.defaultTitle)
        #expect(store.blocks[0].end == F.date(9, 10))
        m.toggleDone(blockID: block.id)
        #expect(store.blocks[0].done)
        var edited = store.blocks[0]; edited.title = "Otro"
        m.save(edited)
        #expect(store.blocks.count == 1 && store.blocks[0].title == "Otro")
        m.delete(blockID: block.id)
        #expect(store.blocks.isEmpty)
    }

    @Test func beginNewPrefillsFromActivityAndNextHour() {
        let m = model()
        let a = F.activity("Parcial", due: F.date(9))
        m.beginNew(at: m.nextHour(after: F.date(8, 10, 20)), activity: a)
        #expect(m.editor?.isNew == true)
        #expect(m.editor?.block.start == F.date(8, 11))
        #expect(m.editor?.block.title == "Estudiar Parcial" && m.editor?.block.activityID == a.id)
    }

    @Test func stepsByMode() {
        let m = model()
        m.step(by: 1)
        #expect(m.anchor == F.date(15, 10))
        m.mode = .month
        m.step(by: -1)
        #expect(m.anchor == F.date(15, 10, month: 9))
    }

    @Test func exportReportsDeniedMessage() async {
        let fake = FakeCalendarStore(); fake.granted = false
        let m = CalendarModel(store: MemoryStudyStore(), calendar: F.cal, now: F.date(8)) { fake }
        await m.export(entries: [], now: F.date(8))
        #expect(m.exportFailed && m.exportMessage?.contains("Calendarios") == true)
    }
}
