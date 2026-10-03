import Testing
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct NativeEnablednessTests {
    @Test("enabledness retains its Boolean type and yields to lexical record bindings")
    func lexicalScope() throws {
        let parser = ParserSession()
        parser.specBindings.atomicSteps["step"] = AtomicStep(model: .init(label: .init(name: "advance"), statements: []))
        let syntax: ExprSyntax = "step.enabled"
        #expect(parser.decodeTypedFacadeValue(syntax, scope: .empty) == .enabledAction("advance"))
        #expect(parser.typedFacadeValueType(syntax, scope: .empty) == .bool)
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "step", to: .variable("local"),
            shape: .record([.init(name: "enabled", type: .bool)]))
        #expect(parser.decodeTypedFacadeValue(syntax, scope: scope) == .recordAccess(.variable("local"), "enabled"))
        #expect(parser.typedFacadeValueType(syntax, scope: scope) == .bool)
    }

    @Test("bound independent steps share enabledness and fairness across configuration, checking, and export")
    func boundSteps() throws {
        let scenario = try #require(BoundStepEnabledness.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 10)
        #expect(graph.transitions.count == 4)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.temporalResults[.Finished]?.status == .satisfied)
        let rendered = try scenario.render().tlaBundle.tla
        #expect(rendered.contains("ENABLED"))
        #expect(rendered.contains("WF_count((\\E amount \\in choices: advance(amount)))"))
        #expect(rendered.contains("SF_count(finish)"))
        let configuration = try BoundStepEnabledness.Configuration(choices: [])
        let empty = try BoundStepEnabledness.makeMachine(configuration: configuration)
        #expect(try empty.enabledActions().isEmpty)
        #expect(try empty.violatedInvariants().isEmpty)
    }

    @Test("Native action guards evaluate enabledness only when demanded")
    func actionGuards() throws {
        let machine = try GuardedEnabledness.makeMachine()
        #expect(try machine.successors(for: .blocked).isEmpty)
        let next = try machine.successors(for: .guardedStay)
        #expect(next.count == 1)
        #expect(next.first?.state == machine.state)
        #expect(throws: (any Error).self) { try machine.successors(for: .divide) }
    }

    @Test("State predicates preserve short-circuit enabledness and demanded failures")
    func statePredicates() throws {
        let machine = try GuardedEnabledness.makeMachine()
        #expect(try machine.satisfiesStateConstraint())
        #expect(try machine.violatedInvariants(checking: [.guardedInvariant]).isEmpty)
        #expect(try machine.matchedReachabilityProperties(checking: [.guardedReachable]) == [.guardedReachable])
        #expect(throws: (any Error).self) { try machine.violatedInvariants(checking: [.demandedInvariant]) }
        #expect(throws: (any Error).self) { try machine.matchedReachabilityProperties(checking: [.demandedReachable]) }
    }
}
