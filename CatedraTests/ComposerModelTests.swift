import Testing
import Foundation
@testable import Catedra

@MainActor
struct ComposerModelTests {
    private func makeModel() -> ComposerModel {
        let model = ComposerModel()
        model.setAvailable(SlashCommandCatalogPolicy.merge(
            app: AppCommand.definitions,
            cli: [SlashCommand(name: "compact", description: "Resume", argumentHint: nil, aliases: [], kind: .builtin),
                  SlashCommand(name: "normas-uft", description: "Formato", argumentHint: "[name]", aliases: [], kind: .skill)],
            local: []))
        return model
    }

    private func type(_ model: ComposerModel, _ text: String) {
        model.userEdited(text: text, selection: NSRange(location: (text as NSString).length, length: 0))
    }

    @Test func slashOpensGroupedPopupWithAppCommandsFirst() {
        let model = makeModel()
        type(model, "/")
        #expect(model.isPopupVisible)
        #expect(model.sections.map(\.title) == ["Cátedra", "Skills", "Comandos de Claude Code"])
        #expect(model.flat.first?.command.kind == .app)
    }

    @Test func popupClosesAfterSpaceAndOnDismiss() {
        let model = makeModel()
        type(model, "/co")
        #expect(model.isPopupVisible)
        model.dismissPopup()
        #expect(!model.isPopupVisible)
        type(model, "/com")
        #expect(model.isPopupVisible)
        type(model, "/compact ")
        #expect(!model.isPopupVisible)
    }

    @Test func acceptingSkillInsertsNameAndSpace() {
        let model = makeModel()
        type(model, "revisa /norm")
        #expect(model.acceptSelected() == .inserted)
        #expect(model.text == "revisa /normas-uft ")
        #expect(!model.isPopupVisible)
    }

    @Test func acceptingAppCommandWithoutArgsExecutesAndRemovesToken() {
        let model = makeModel()
        type(model, "/resu")
        #expect(model.acceptSelected() == .execute(.resume))
        #expect(model.text == "")
    }

    @Test func acceptingAppCommandWithArgsOnlyInserts() {
        let model = makeModel()
        type(model, "/mod")
        #expect(model.acceptSelected() == .inserted)
        #expect(model.text == "/model ")
    }

    @Test func selectionWrapsAndResetsOnNewQuery() {
        let model = makeModel()
        type(model, "/")
        model.moveSelection(by: -1)
        #expect(model.selectedIndex == model.flat.count - 1)
        type(model, "/c")
        #expect(model.selectedIndex == 0)
    }

    @Test func historyRecallsFromEmptyComposerAndRestoresIt() {
        let model = makeModel()
        model.history = PromptHistory(entries: ["uno", "dos"])
        #expect(model.historyPrevious())
        #expect(model.text == "dos")
        #expect(model.historyPrevious())
        #expect(model.text == "uno")
        #expect(model.historyNext())
        #expect(model.historyNext())
        #expect(model.text == "")
    }

    @Test func historyDoesNotReplaceTypedDraft() {
        let model = makeModel()
        model.history = PromptHistory(entries: ["uno", "dos"])
        type(model, "borrador\nsegunda línea")
        #expect(!model.historyPrevious())
        #expect(model.text == "borrador\nsegunda línea")
    }

    @Test func editingARecalledPromptStopsHistoryNavigation() {
        let model = makeModel()
        model.history = PromptHistory(entries: ["uno", "dos"])
        #expect(model.historyPrevious())
        type(model, "dos editado")
        #expect(!model.historyPrevious())
        #expect(model.text == "dos editado")
    }

    @Test func insertingReferencesAppendsAtCaret() {
        let model = makeModel()
        type(model, "mira")
        model.insertReferences(["@a.pdf"])
        #expect(model.text == "mira @a.pdf ")
        #expect(model.selection.location == 12)
    }
}
