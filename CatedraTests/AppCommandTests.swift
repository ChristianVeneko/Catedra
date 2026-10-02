import Testing
import Foundation
@testable import Catedra

struct AppCommandTests {
    @Test func parsesSimpleCommands() {
        #expect(AppCommand.parse("/resume") == .resume)
        #expect(AppCommand.parse("/new") == .newConversation)
        #expect(AppCommand.parse("/clear") == .newConversation)
        #expect(AppCommand.parse("/recetas") == .recipes)
        #expect(AppCommand.parse("/terminal") == .terminal)
        #expect(AppCommand.parse("/archivos") == .files)
    }

    @Test func parsesModelArgument() {
        #expect(AppCommand.parse("/model sonnet") == .setModel(.sonnet))
        #expect(AppCommand.parse("  /model  OPUS  ") == .setModel(.opus))
        #expect(AppCommand.parse("/model predeterminado") == .setModel(.default))
        #expect(AppCommand.parse("/model default") == .setModel(.default))
    }

    @Test func invalidOrMissingArgumentsAreReported() {
        if case .invalid(let message) = AppCommand.parse("/model gpt") { #expect(message.contains("opus")) }
        else { Issue.record("expected invalid") }
        if case .invalid = AppCommand.parse("/model") {} else { Issue.record("expected invalid") }
        if case .invalid = AppCommand.parse("/permisos") {} else { Issue.record("expected invalid") }
    }

    @Test func parsesPermissionModes() {
        #expect(AppCommand.parse("/permisos auto") == .setPermissionMode(.auto))
        #expect(AppCommand.parse("/permisos acceptEdits") == .setPermissionMode(.acceptEdits))
        #expect(AppCommand.parse("/permisos aceptar") == .setPermissionMode(.acceptEdits))
        #expect(AppCommand.parse("/permisos sin-restricciones") == .setPermissionMode(.bypassPermissions))
        #expect(AppCommand.parse("/permisos bypassPermissions") == .setPermissionMode(.bypassPermissions))
    }

    @Test func nonAppCommandsAndPlainTextAreNotParsed() {
        #expect(AppCommand.parse("/normas-uft revisa esto") == nil)
        #expect(AppCommand.parse("hola /model sonnet") == nil)
        #expect(AppCommand.parse("") == nil)
        #expect(AppCommand.parse("/compact") == nil)
    }

    @Test func simpleCommandsRejectExtraTextAsUnknownToApp() {
        // "/new algo" is still the app command; arguments are ignored.
        #expect(AppCommand.parse("/new algo") == .newConversation)
    }

    @Test func definitionsExposeAppCommandsForThePopup() {
        let names = AppCommand.definitions.map(\.name)
        #expect(names.contains("resume") && names.contains("model") && names.contains("permisos"))
        #expect(AppCommand.definitions.allSatisfy { $0.kind == .app })
        #expect(AppCommand.definitions.first { $0.name == "new" }?.aliases == ["clear"])
    }

    @Test func executesImmediatelyOnlyWithoutRequiredArguments() {
        #expect(AppCommand.definitions.first { $0.name == "resume" }?.argumentHint == nil)
        #expect(AppCommand.definitions.first { $0.name == "model" }?.argumentHint != nil)
    }
}
