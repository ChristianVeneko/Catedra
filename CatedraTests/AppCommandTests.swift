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
        #expect(AppCommand.parse("/model sonnet") == .setModel("sonnet"))
        #expect(AppCommand.parse("  /model  OPUS  ") == .setModel("opus"))
        #expect(AppCommand.parse("/model predeterminado") == .setModel(nil))
        #expect(AppCommand.parse("/model default") == .setModel(nil))
    }

    @Test func invalidOrMissingArgumentsAreReported() {
        if case .invalid(let message) = AppCommand.parse("/model gpt") { #expect(message.contains("opus")) }
        else { Issue.record("expected invalid") }
        if case .invalid = AppCommand.parse("/model") {} else { Issue.record("expected invalid") }
        if case .invalid = AppCommand.parse("/permisos") {} else { Issue.record("expected invalid") }
    }

    @Test func parsesPermissionModes() {
        #expect(AppCommand.parse("/permisos auto") == .setPermission(.automatic))
        #expect(AppCommand.parse("/permisos acceptEdits") == .setPermission(.acceptEdits))
        #expect(AppCommand.parse("/permisos aceptar") == .setPermission(.acceptEdits))
        #expect(AppCommand.parse("/permisos sin-restricciones") == .setPermission(.unrestricted))
        #expect(AppCommand.parse("/permisos bypassPermissions") == .setPermission(.unrestricted))
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

    @Test func readOnlyAndProviderSpecificPermissions() {
        #expect(AppCommand.parse("/permisos solo-lectura") == .setPermission(.readOnly))
        #expect(AppCommand.parse("/permisos plan", provider: .antigravity) == .setPermission(.readOnly))
        if case .invalid(let message) = AppCommand.parse("/permisos auto", provider: .antigravity) {
            #expect(message.contains("Antigravity"))
        } else { Issue.record("auto must be rejected for Antigravity") }
        if case .invalid = AppCommand.parse("/permisos auto", provider: .opencode) {} else { Issue.record("expected invalid") }
    }

    @Test func modelValidationDependsOnProvider() {
        let agy = [AgentModelOption(id: "gemini-3.1-pro-high", label: "Gemini 3.1 Pro (High)")]
        #expect(AppCommand.parse("/model gemini-3.1-pro-high", provider: .antigravity, models: agy) == .setModel("gemini-3.1-pro-high"))
        #expect(AppCommand.parse("/model Gemini 3.1 Pro (High)", provider: .antigravity, models: agy) == .setModel("gemini-3.1-pro-high"))
        if case .invalid = AppCommand.parse("/model nada", provider: .antigravity, models: agy) {} else { Issue.record("expected invalid") }
        #expect(AppCommand.parse("/model ollama/qwen3", provider: .opencode, models: []) == .setModel("ollama/qwen3"))
        #expect(AppCommand.parse("/model predeterminado", provider: .opencode) == .setModel(nil))
    }

    @Test func hintsListOnlySupportedPermissions() {
        let claude = AppCommand.definitions(for: .claude).first { $0.name == "permisos" }?.argumentHint
        let agy = AppCommand.definitions(for: .antigravity).first { $0.name == "permisos" }?.argumentHint
        #expect(claude?.contains("auto") == true)
        #expect(agy?.contains("auto") == false)
    }
}
