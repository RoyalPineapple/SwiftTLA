import Testing
@testable import SwiftTLA

struct ActionFrameConditionTests {
    @Test("UNCHANGED constrains assignments and choices to the original state")
    func unchangedRejectsConflictingUpdatesInEitherOrder() throws {
        let unchanged = ActionExpr.unchanged(.named("value"))
        let updates: [ActionExpr] = [
            .assign(.named("value"), .int(1)),
            .chooseAction(.named("value"), .setLiteral([.int(1)]))
        ]
        for update in updates {
            for body in [ActionExpr.and(update, unchanged), .and(unchanged, update)] {
                let compilation = try canonicalTestSpec(
                    variables: [("value", .value(.int(0)))], actions: [("change", body, [])]
                ).compile()
                let runtime = CompiledRuntime(compilation: compilation)
                let initial = try #require(try runtime.initialStates().first)
                #expect(throws: CompiledEvaluationError.self) {
                    try runtime.successors(from: initial)
                }
            }
        }
    }

    @Test("UNCHANGED permits matching assignments and independent updates")
    func unchangedPreservesConsistentFrameConditions() throws {
        let compilation = try canonicalTestSpec(
            variables: [("value", .value(.int(0))), ("other", .value(.int(0)))],
            actions: [("change", .and(
                .unchanged(.named("value")),
                .and(.assign(.named("value"), .int(0)), .assign(.named("other"), .int(1)))
            ), [])]
        ).compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let next = try #require(try runtime.successors(from: initial).first)
        let unchanged = try #require(compilation.layout.testVariableID(named: "value"))
        let updated = try #require(compilation.layout.testVariableID(named: "other"))
        #expect(try next.state.value(for: unchanged) == .integer(0))
        #expect(try next.state.value(for: updated) == .integer(1))
    }
}
