import Testing
@testable import Catedra

struct DependencyCheckTests {
    // MARK: version parsing / comparison

    @Test func parsesVersionsFromCommandOutput() {
        #expect(SemanticVersion.parse("Python 3.14.0") == SemanticVersion(3, 14, 0))
        #expect(SemanticVersion.parse("git version 2.50.1 (Apple Git-155)") == SemanticVersion(2, 50, 1))
        #expect(SemanticVersion.parse("v22.3") == SemanticVersion(22, 3, 0))
        #expect(SemanticVersion.parse("2.1.288 (Claude Code)")?.description == "2.1.288")
        #expect(SemanticVersion.parse("no version here") == nil)
        #expect(SemanticVersion.parse("") == nil)
    }

    @Test func comparesNumericallyNotLexically() {
        #expect(SemanticVersion(3, 10, 0) > SemanticVersion(3, 9, 18))
        #expect(SemanticVersion(3, 9, 0) >= SemanticVersion(3, 9))
        #expect(SemanticVersion(2, 7, 18) < SemanticVersion(3, 9))
        #expect(SemanticVersion(3, 9) == SemanticVersion(3, 9, 0))
    }

    // MARK: evaluation

    private let python = DependencySpec(id: .python, name: "Python 3", requirement: .required,
                                        minimumVersion: SemanticVersion(3, 9), installCommand: "brew install python")

    @Test func foundWithEnoughVersionIsOk() {
        let check = DependencyEvaluator.evaluate(python, .found(path: "/usr/bin/python3", output: "Python 3.12.1"))
        #expect(check.status == .ok)
        #expect(check.version == "3.12.1")
        #expect(check.detail == "/usr/bin/python3")
        #expect(check.blocksReadiness == false)
    }

    @Test func tooOldVersionIsOutdatedAndBlocksWhenRequired() {
        let check = DependencyEvaluator.evaluate(python, .found(path: "/usr/bin/python3", output: "Python 3.8.2"))
        #expect(check.status == .outdated(found: "3.8.2", minimum: "3.9.0"))
        #expect(check.blocksReadiness)
    }

    @Test func missingRequiredBlocksButMissingOptionalDoesNot() {
        let optional = DependencySpec(id: .git, name: "Git", requirement: .optional)
        #expect(DependencyEvaluator.evaluate(python, .notFound).blocksReadiness)
        let git = DependencyEvaluator.evaluate(optional, .notFound)
        #expect(git.status == .missing)
        #expect(git.blocksReadiness == false)
    }

    @Test func foundWithoutParsableVersionIsStillOkWhenNoMinimum() {
        let spec = DependencySpec(id: .node, name: "Node", requirement: .optional)
        let check = DependencyEvaluator.evaluate(spec, .found(path: "/x/node", output: nil))
        #expect(check.status == .ok)
        #expect(check.version == nil)
    }

    @Test func unparsableVersionFailsAMinimum() {
        let check = DependencyEvaluator.evaluate(python, .found(path: "/x/python3", output: "weird"))
        if case .outdated = check.status {} else { Issue.record("expected outdated") }
    }

    @Test func failedProbeReportsReasonAsMissing() {
        let check = DependencyEvaluator.evaluate(python, .failed("timeout"))
        #expect(check.status == .missing)
        #expect(check.detail == "timeout")
    }

    // MARK: plan & readiness

    @Test func planMarksSelectedAgentRequiredAndOthersOptional() {
        let specs = DependencyPlan.specs(selectedAgent: .opencode)
        func requirement(_ id: DependencyID) -> DependencyRequirement? { specs.first { $0.id == id }?.requirement }
        #expect(requirement(.python) == .required)
        #expect(requirement(.requests) == .required)
        #expect(requirement(.agent(.opencode)) == .required)
        #expect(requirement(.agent(.claude)) == .optional)
        #expect(requirement(.agent(.antigravity)) == .optional)
        #expect(requirement(.git) == .optional)
        #expect(requirement(.node) == .optional)
        #expect(specs.first { $0.id == .python }?.minimumVersion == SemanticVersion(3, 9))
        #expect(specs.first { $0.id == .agent(.claude) }?.installCommand == "curl -fsSL https://claude.ai/install.sh | bash")
        #expect(specs.first { $0.id == .requests }?.installCommand == "python3 -m pip install --user requests")
    }

    @Test func readinessListsBlockingChecks() {
        let ok = DependencyCheck(id: .python, name: "Python 3", requirement: .required, status: .ok)
        let missing = DependencyCheck(id: .requests, name: "requests", requirement: .required, status: .missing)
        let optional = DependencyCheck(id: .git, name: "Git", requirement: .optional, status: .missing)
        #expect(DependencyEvaluator.readiness([ok, optional]) == .ready)
        #expect(DependencyEvaluator.readiness([ok, missing, optional]) == .blocked([.requests]))
        #expect(DependencyEvaluator.readiness([]) == .ready)
    }

    @Test func checkingRequiredIsNotReadyYet() {
        let pending = DependencyCheck(id: .python, name: "Python 3", requirement: .required, status: .checking)
        #expect(DependencyEvaluator.readiness([pending]) == .checking)
    }
}
