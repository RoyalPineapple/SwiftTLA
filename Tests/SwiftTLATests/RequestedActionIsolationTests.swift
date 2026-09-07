import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Formal parity fixture keeps both independent actions enabled at the same state.
@TLAModel
private struct IndependentActionFaults {
    static var spec: TLASpec {
        TLASpec("IndependentActionFaults") {
            let count = Var<Int>("count")
            Variable(count, 0)
            let ceiling = Var<Int>("ceiling")
            Variable(ceiling, 9_223_372_036_854_775_807)
            SwiftTLA.Action("valid") { count.becomes(count + 1) }
            SwiftTLA.Action("invalid") { count.becomes(ceiling + 1) }
            Invariant("Nonnegative") { count >= 0 }
            Constraint(count >= 0)
        }
    }
}

@Suite struct RequestedActionIsolationTests {
    @Test("requested actions and independent predicates do not execute unrelated actions")
    func requestedActionIsolatedFromFault() throws {
        let compilation = try IndependentActionFaults.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let valid = try #require(compilation.layout.testActionID(named: "valid"))
        let count = try #require(compilation.layout.testVariableID(named: "count"))
        let invariant = try #require(compilation.semantics.invariants.first)
        let successors = try runtime.successors(for: valid, from: initial)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        #expect(try successor.state.value(for: count) == .integer(1))
        #expect(try runtime.invariantHolds(invariant, in: initial))
        #expect(try runtime.predicateHolds(invariant.body, in: initial))
        #expect(try runtime.evaluate([invariant.body], in: initial) == [.boolean(true)])
        var native = try IndependentActionFaults.makeMachine()
        #expect(try native.isEnabled(.valid))
        #expect(try native.violatedInvariants().isEmpty)
        #expect(try native.send(.valid).after.count == 1)
        #expect(try successor.state.value(for: count) == .integer(native.state.count))
        #expect(throws: EvalError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try runtime.successors(from: initial)
        }
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try native.enabledActions()
        }
    }
    @Test("transitive ENABLED dependencies retain complete action enumeration")
    func enabledDependenciesRemainComplete() throws {
        let compilation = try TLASpec(
            name: "EnabledDependency",
            variables: [.init(name: "count", initialization: .value(.int(0)), origin: .compiler)],
            actions: [
                .init(name: "valid", body: .unchanged(.named("count"))),
                .init(name: "invalid", body: .assign(.named("count"), .add(.int(Int.max), .int(1)))),
                .init(name: "probe", body: .guard_(.operatorApplication(.reference("IsEnabled", arity: 0), []))),
            ],
            invariants: [.init(name: "Enabled", body: .operatorApplication(.reference("IsEnabled", arity: 0), []))],
            formalOperatorDefinitions: [.init(name: "IsEnabled", parameters: [], body: .enabledAction("valid"))]
        ).compile()
        let plan = NativeMachinePlan(compilation: compilation)
        let probe = try #require(compilation.layout.testActionID(named: "probe"))
        let action = try #require(plan.actions.first { $0.id == probe })
        let invariant = try #require(plan.invariants.first)
        #expect(plan.requiresEnabledActions(in: action.body))
        #expect(plan.requiresEnabledActions(in: invariant.body))
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        #expect(throws: EvalError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try runtime.successors(for: probe, from: initial)
        }
        #expect(throws: EvalError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try runtime.invariantHolds(invariant, in: initial)
        }
    }

}
