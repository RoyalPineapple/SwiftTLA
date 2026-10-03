import Testing
@testable import SwiftTLA

@Suite("symmetry must not hide counterexamples")
struct SymmetryCounterexampleTests {
    @Test("an identity-dependent symmetry cannot hide a reachable invariant violation")
    func rejectsReductionThatHidesViolation() throws {
        let a = TLAValue.constant("a")
        let b = TLAValue.constant("b")
        let specification = canonicalTestSpec(
            variables: [("member", .value(a))],
            actions: [("advance", .assign(.named("member"), .value(b)), [])],
            invariants: [("staysA", .equal(.variable("member"), .value(a)))],
            symmetrySets: [.init(variableName: "Members", values: [a, b])]
        )
        let compilation = try specification.compile()
        let raw = try ModelChecker(compilation: compilation, configuration: .init(
            maximumStateLimit: 10, symmetryReduction: .disabled
        )).check()
        guard case .invariantViolated = raw else {
            Issue.record("The unreduced model must expose the reachable violation.")
            return
        }
        #expect(throws: FiniteExplorationConfigurationError.symmetryReductionNotSupportedByFormalExplorer) {
            _ = try ModelChecker(compilation: compilation, configuration: .init(
                maximumStateLimit: 10, symmetryReduction: .enabled(maximumPermutationCount: 2)
            )).check()
        }
    }

}
