import Testing
import Foundation
@testable import Catedra

struct ActivityStateTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func pendingWithFutureDue() {
        let a = makeActivity(due: now.addingTimeInterval(3600))
        #expect(ActivityState.derive(from: a, hasUserWork: false, now: now) == .pending)
    }

    @Test func inProgressWhenUserFilesExist() {
        let a = makeActivity(due: now.addingTimeInterval(3600))
        #expect(ActivityState.derive(from: a, hasUserWork: true, now: now) == .inProgress)
    }

    @Test func upcomingWhenNotYetOpen() {
        let a = makeActivity(due: now.addingTimeInterval(86400), status: "Proximo (aun no abre)")
        #expect(ActivityState.derive(from: a, hasUserWork: false, now: now) == .upcoming)
    }

    @Test func overdueWhenPastDueAndNotSubmitted() {
        let a = makeActivity(due: now.addingTimeInterval(-60))
        #expect(ActivityState.derive(from: a, hasUserWork: true, now: now) == .overdue)
    }

    @Test func submittedByStatusKeyword() {
        let a = makeActivity(due: now.addingTimeInterval(-60), status: "Entregado")
        #expect(ActivityState.derive(from: a, hasUserWork: false, now: now) == .submitted)
    }

    @Test func submittedWhenGradePresent() {
        let a = makeActivity(due: now.addingTimeInterval(-60), grade: "18,00 / 20,00")
        #expect(ActivityState.derive(from: a, hasUserWork: false, now: now) == .submitted)
    }

    @Test func undatedPendingStaysPending() {
        let a = makeActivity(due: nil)
        #expect(ActivityState.derive(from: a, hasUserWork: false, now: now) == .pending)
    }

    @Test func kindMapping() {
        #expect(ActivityKind(rawType: "Tarea") == .tarea)
        #expect(ActivityKind(rawType: "Cuestionario") == .cuestionario)
        #expect(ActivityKind(rawType: "Examen") == .examen)
        #expect(ActivityKind(rawType: "Foro") == .other("Foro"))
        #expect(ActivityKind.tarea.symbolName == "doc.text")
        #expect(ActivityKind.cuestionario.symbolName == "checklist")
        #expect(ActivityKind.examen.symbolName == "graduationcap")
        #expect(ActivityKind.other("x").symbolName == "circle")
    }
}
