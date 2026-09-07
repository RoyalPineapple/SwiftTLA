import Testing
@testable import SwiftTLA

@Suite struct ActionPredicateContractTests {
    @Test("Non-Boolean action conditions cannot silently disable actions or select ELSE")
    func invalidConditionsFailEvaluation() throws {
        for body: ActionExpr in [
            .guard_(.int(1)),
            .ifElse(.int(1), .assign(.named("x"), .int(1)), .assign(.named("x"), .int(2)))
        ] {
            let compilation = try canonicalTestSpec(
                variables: [("x", .value(.int(0)))], actions: [("step", body, [])]
            ).compile()
            let runtime = CompiledRuntime(compilation: compilation)
            let initial = try #require(try runtime.initialStates().first)
            #expect(throws: EvalError.expected(.boolean, actual: [.integer(1)])) {
                try runtime.successors(from: initial)
            }
        }
    }
}
