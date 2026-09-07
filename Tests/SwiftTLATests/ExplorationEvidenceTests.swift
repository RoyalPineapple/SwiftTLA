import Testing
@testable import SwiftTLA

@Suite("compiled exploration evidence")
struct ExplorationEvidenceTests {
    @Test("property checks reject missing, inconsistent, and foreign state evidence")
    func rejectsInvalidEvidence() throws {
        let abstractValue = Var<Int>("abstractValue", 0)
        let abstract = TLASpec("AbstractEvidence") { Variable(abstractValue) }
        let instance = Instance("C", of: abstract)
        let concreteValue = Var<Int>("concreteValue", 0)
        let concrete = TLASpec("ConcreteEvidence") {
            Variable(concreteValue)
            Action("stay") { concreteValue.stays }
            Always("stable", concreteValue == 0)
            instance
            Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
        }
        let compilation = try concrete.compile()
        let configuration = try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)
        let explored = try ModelChecker(compilation: compilation, configuration: configuration).explore()
        let initial = try #require(explored.initialStateIDs.first)
        let missing = StateGraph.StateID(999)
        let foreign = try abstract.compile()
        let cases: [([StateGraph.StateID], CompilationIdentity, [StateGraph.StateID: CompiledState])] = [
            ([initial], compilation.identity, [:]),
            ([], compilation.identity, explored.compiledStates),
            ([missing], compilation.identity, explored.compiledStates),
            ([initial], foreign.identity, explored.compiledStates),
            ([initial], compilation.identity, [initial: try CompiledState(values: [.integer(1)], compilation: compilation)]),
            ([initial], compilation.identity, [initial: try CompiledState(values: [.integer(0)], compilation: foreign)])
        ]
        for (initials, identity, states) in cases {
            let invalid = FiniteExploration(
                graph: explored.graph, initialStateIDs: initials, outcome: explored.outcome,
                compilationIdentity: identity, configuration: configuration, compiledStates: states
            )
            do {
                _ = try RefinementChecker(compilation: compilation).check(invalid)
                Issue.record("Expected invalid refinement evidence to be rejected.")
            } catch is CompilationDiagnostic {
            } catch is CompiledEvaluationError {
            }
            do {
                _ = try invalid.analyzeTemporalProperties(in: compilation)
                Issue.record("Expected invalid temporal evidence to be rejected.")
            } catch is CompilationDiagnostic {
            } catch is CompiledEvaluationError {
            }
        }
        let dangling = FiniteExploration(
            graph: .init(
                specName: explored.graph.specName, variableNames: explored.graph.variableNames,
                transitions: [initial: [.init(label: try #require(explored.graph.transitions[initial]?.first?.label), target: missing)]],
                states: explored.graph.states
            ),
            initialStateIDs: [initial], outcome: explored.outcome,
            compilationIdentity: compilation.identity, configuration: configuration, compiledStates: explored.compiledStates
        )
        #expect(throws: CompilationDiagnostic.self) {
            _ = try RefinementChecker(compilation: compilation).check(dangling)
        }
    }
}
