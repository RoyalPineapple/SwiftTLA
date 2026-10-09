import Testing
@testable import SwiftTLA

struct ActionFrameConditionTests {
    @Test("Frame completion preserves shared effects and short-circuited continuations")
    func completionKeepsEffectOrder() {
        let variables = [NamedVar(name: "value", initial: .int(0))]
        let register = CheckingRegisterReference(name: "visits")
        let write = ActionExpr.guard_(.setCheckingRegister(register,
            .add(.checkingRegister(register), .int(1))))
        let assignment = ActionExpr.assign(.named("value"), .int(1))
        let disabled = ActionExpr.guard_(.bool(false))
        let action = ActionExpr.and(write, .or(assignment, disabled))
        #expect(ActionNormalization.complete(action, variables: variables) == action)
        #expect(ActionNormalization.complete(.and(write, .and(disabled, assignment)),
            variables: variables) == .and(write, disabled))
    }

    @Test("Frame completion cannot capture a continuation's state reads")
    func completionRenamesOnlyCapturingBinders() throws {
        let compilation = try canonicalTestSpec(
            variables: [("value", .value(.int(3))), ("copied", .value(.int(0)))],
            actions: [("copy", .and(
                .existsAction("value", .setLiteral([.int(1)]), .guard_(.bool(true))),
                .assign(.named("copied"), .variable("value"))
            ), [])]
        ).compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let next = try #require(try runtime.successors(from: initial).first)
        let copied = try #require(compilation.layout.testVariableID(named: "copied"))
        #expect(try next.state.value(for: copied) == .integer(3))
    }

    @Test("UNCHANGED constrains assignments and choices to the original state")
    func unchangedRejectsConflictingUpdatesInEitherOrder() throws {
        let unchanged = ActionExpr.unchanged(.named("value"))
        let updates: [ActionExpr] = [
            .assign(.named("value"), .int(1)),
            .existsAction("selected", .setLiteral([.int(1)]), .assign(.named("value"), .variable("selected")))
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
