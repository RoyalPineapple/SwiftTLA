import Testing
@testable import SwiftTLA

@Suite("concrete edges for temporal and refinement verification")
struct ConcreteVerificationGraphTests {
    @Test("temporal checks require explicit unreduced exploration")
    func temporalChecksRequireConcreteStates() throws {
        let a = TLAValue.constant("a")
        let b = TLAValue.constant("b")
        let specification = canonicalTestSpec(
            variables: [("member", .value(a))],
            actions: [("swap", .assign(.named("member"), .ifThenElse(
                .equal(.variable("member"), .value(a)), .value(b), .value(a)
            )), [])],
            temporal: [("visitsB", .alwaysEventually(.equal(.variable("member"), .value(b))))],
            fairness: [.weakFairness("swap")],
            symmetrySets: [.init(variableName: "Members", values: [a, b])]
        )
        let compilation = try specification.compile()
        let reduced = ModelChecker(
            compilation: compilation,
            configuration: try .init(maximumStateLimit: 10, symmetryReduction: .enabled(maximumPermutationCount: 2))
        )
        #expect(throws: FiniteExplorationConfigurationError.symmetryReductionRequiresSafetyOnly) {
            _ = try reduced.explore()
        }
        #expect(throws: FiniteExplorationConfigurationError.symmetryReductionRequiresSafetyOnly) {
            _ = try reduced.checkLiveness()
        }
        let concrete = ModelChecker(
            compilation: compilation,
            configuration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled)
        )
        let exploration = try concrete.explore()
        #expect(exploration.graph.states.count == 2)
        #expect(try exploration.analyzeTemporalProperties(in: compilation).first?.status == .satisfied)
        let reductionEvidence = FiniteExploration(
            graph: exploration.graph, initialStateIDs: exploration.initialStateIDs,
            outcome: exploration.outcome, compilationIdentity: compilation.identity,
            configuration: reduced.configuration, compiledStates: exploration.compiledStates
        )
        #expect(throws: FiniteExplorationConfigurationError.symmetryReductionRequiresSafetyOnly) {
            _ = try reductionEvidence.analyzeTemporalProperties(in: compilation)
        }
        guard case .ok(statesCount: 2) = try concrete.checkLiveness() else {
            Issue.record("Expected fairness to force both concrete member states to recur.")
            return
        }
        let safetyOnly = TLASpec(
            name: specification.name, variables: specification.variables,
            actions: specification.actions, invariants: [], symmetrySets: specification.symmetrySets
        )
        #expect(try ModelChecker(compilation: safetyOnly.compile(), configuration: .init(
            maximumStateLimit: 10, symmetryReduction: .enabled(maximumPermutationCount: 2)
        )).explore().graph.states.count == 1)
    }

    @Test("refinement rejects reduction that could hide an unmapped concrete step")
    func refinementRequiresConcreteTargets() throws {
        let abstractValue = Var<String>("abstractValue", "a")
        let abstract = TLASpec("AbstractConcreteEdges") {
            Variable(abstractValue)
            Action("stay") { abstractValue.stays }
        }
        let concreteValue = Var<String>("concreteValue", "a")
        let instance = Instance("C", of: abstract)
        let concrete = TLASpec("ConcreteEdges") {
            Variable(concreteValue)
            Action("advance") { concreteValue.becomes("b").when(concreteValue == "a") }
            Symmetry("Members", Set(["a", "b"]))
            instance
            Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
        }
        let compilation = try concrete.compile()
        #expect(throws: FiniteExplorationConfigurationError.symmetryReductionRequiresSafetyOnly) {
            _ = try ModelChecker(compilation: compilation, configuration: .init(
                maximumStateLimit: 10, symmetryReduction: .enabled(maximumPermutationCount: 2)
            )).check()
        }
        let outcome = try ModelChecker(compilation: compilation, configuration: .init(
            maximumStateLimit: 10, symmetryReduction: .disabled
        )).check()
        guard case .refinementViolated(_, .transition) = outcome else {
            Issue.record("The concrete a-to-b edge must not be hidden as a representative self-edge.")
            return
        }
    }
}
