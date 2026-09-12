import Testing
@testable import SwiftTLA

@Suite("concrete counterexamples from symmetry-reduced graphs")
struct SymmetryCounterexampleTests {
    @Test("every reported action reaches the next concrete trace state")
    func replaysRenamedMemberTransitions() throws {
        let a = TLAValue.constant("a")
        let b = TLAValue.constant("b")
        let members = StateExpr.value(.set([a, b]))
        let specification = TLASpec(
            name: "SymmetryCounterexample",
            variables: [.init(
                name: "marked", initialization: .value(.function([a: .int(0), b: .int(0)])), origin: .compiler
            )],
            actions: [.init(name: "mark", body: .assign(.named("marked"), .except(
                .variable("marked"), .variable("selected"), .int(1)
            )), bindings: [.init(name: "selected", values: [a, b])])],
            invariants: [.init(name: "oneUnmarked", body: .lessThan(.setSum(.variable("marked"), members), .int(2)))],
            symmetrySets: [.init(variableName: "Members", values: [a, b])]
        )
        let compilation = try specification.compile()
        let exploration = try ModelChecker(compilation: compilation, configuration: .init(
            maximumStateLimit: 10, symmetryReduction: .enabled(maximumPermutationCount: 2)
        )).explore()
        guard case .invariantViolated(_, let failing, let trace) = exploration.outcome else {
            Issue.record("Expected a counterexample after marking both members.")
            return
        }
        #expect(exploration.graph.states.count == 3)
        #expect(trace.count == 3)
        let runtime = CompiledRuntime(compilation: compilation)
        var concrete = try #require(try runtime.initialStates().first)
        #expect(try trace.first?.state == concrete.projection(using: compilation.layout))
        for step in trace.dropFirst() {
            let successors = try runtime.successors(from: concrete)
            concrete = try #require(try successors.first { successor in
                let arguments = try successor.arguments.map { try $0.rendered(using: compilation.layout) }
                let action = formalActionCall(
                    named: compilation.layout.actions[successor.action.ordinal].declaration.name,
                    arguments: arguments
                )
                return try action == step.action && successor.state.projection(using: compilation.layout) == step.state
            }).state
        }
        #expect(try failing == concrete.projection(using: compilation.layout))
        let invariant = try #require(compilation.semantics.behavior.invariants.first)
        #expect(try !runtime.invariantHolds(invariant, in: concrete))
    }

    @Test("an invalid symmetry cannot manufacture an invariant violation")
    func rejectsAReplayThatDoesNotViolateTheInvariant() throws {
        let a = TLAValue.constant("a")
        let b = TLAValue.constant("b")
        let specification = canonicalTestSpec(
            variables: [("member", .value(b))],
            invariants: [("isB", .equal(.variable("member"), .value(b)))],
            symmetrySets: [.init(variableName: "Members", values: [a, b])]
        )
        do {
            _ = try ModelChecker(compilation: specification.compile(), configuration: .init(
                maximumStateLimit: 10, symmetryReduction: .enabled(maximumPermutationCount: 2)
            )).check()
            Issue.record("Expected a diagnostic when a canonical failure has no concrete witness.")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "counterexample.replay")
        }
    }
}
