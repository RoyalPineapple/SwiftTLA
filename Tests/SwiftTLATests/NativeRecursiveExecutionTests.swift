import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Formal boundary fixture: addition occurs after the recursive call returns.
@TLAModel
private struct RecursiveCounting {
    static var spec: TLASpec {
        TLASpec("RecursiveCounting") {
            let result = Var<Int>("result")
            Variable(result, 0)
            FormalDefinition("Count", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: 0,
                else: 1 + StateExpr.operatorApplication(.reference("Count", arity: 1), [
                    .value(StateExpr.variable("remaining") - 1)
                ])
            ))
            SwiftTLA.Action("count") { result.becomes(FormalCall("Count", 4095)) }
            SwiftTLA.Action("tooDeep") { result.becomes(FormalCall("Count", 4096)) }
            FormalDefinition("Overflow", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: 0,
                else: 9_223_372_036_854_775_807 + StateExpr.operatorApplication(.reference("Overflow", arity: 1), [
                    .value(StateExpr.variable("remaining") - 1)
                ])
            ))
            SwiftTLA.Action("overflow") { result.becomes(FormalCall("Overflow", 1000)) }
            FormalDefinition("Subtract", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: 0,
                else: StateExpr.variable("remaining") - StateExpr.operatorApplication(.reference("Subtract", arity: 1), [
                    .value(StateExpr.variable("remaining") - 1)
                ])
            ))
            SwiftTLA.Action("subtract") { result.becomes(FormalCall("Subtract", 1000)) }
        }
    }
}

@TLAModel
private struct RecursiveMembers {
    static var spec: TLASpec {
        TLASpec("RecursiveMembers") {
            let members = Var<SetExpr<Int>>("members")
            Variable(members, TLAValue.set([]))
            FormalDefinition("Collect", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: StateExpr.set([0]),
                else: StateExpr.set([StateExpr.variable("remaining")]).union(
                    StateExpr.operatorApplication(.reference("Collect", arity: 1), [
                        .value(StateExpr.variable("remaining") - 1)
                    ])
                )
            ))
            SwiftTLA.Action("collect") { members.becomes(FormalCall("Collect", 128)) }
        }
    }
}

@Suite struct NativeRecursiveExecutionTests {
    @Test("non-tail recursive execution matches the formal result within its call budget")
    func boundedNonTailRecursion() throws {
        let compilation = try RecursiveCounting.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let cases: [(String, RecursiveCounting.Action, Int)] = [("count", .count, 4095), ("subtract", .subtract, 500)]
        for (name, action, expected) in cases {
            let id = try #require(compilation.layout.testActionID(named: name))
            let successor = try #require(try runtime.successors(for: id, from: initial).first)
            #expect(try successor.state.value(for: result) == .integer(expected))
            var native = try RecursiveCounting.makeMachine()
            #expect(try native.send(action).after.result == expected)
        }
    }
    @Test("non-tail recursion preserves call-budget and return-arithmetic failures without committing state")
    func recursiveFailuresAreTransactional() throws {
        let compilation = try RecursiveCounting.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let exhausted = try #require(compilation.layout.testActionID(named: "tooDeep"))
        let overflow = try #require(compilation.layout.testActionID(named: "overflow"))
        #expect(throws: EvalError.recursionDepthExceeded(4096)) {
            try runtime.successors(for: exhausted, from: initial)
        }
        #expect(throws: EvalError.integerOverflow(.addition, operands: [Int.max, Int.max])) {
            try runtime.successors(for: overflow, from: initial)
        }
        var native = try RecursiveCounting.makeMachine()
        let before = native.state
        #expect(throws: NativeMachineEvaluationError.recursionDepthExceeded(4096)) { try native.send(.tooDeep) }
        #expect(native.state == before)
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, Int.max])) { try native.send(.overflow) }
        #expect(native.state == before)
    }

    @Test("suspended collection returns preserve native set values")
    func recursiveSetConstruction() throws {
        let compilation = try RecursiveMembers.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "collect"))
        let members = try #require(compilation.layout.testVariableID(named: "members"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var native = try RecursiveMembers.makeMachine()
        let after = try native.send(.collect).after
        #expect(after.members == Set(0...128))
        #expect(try successor.state.value(for: members) == .set(Set((0...128).map(CompiledValue.integer))))
    }

}
