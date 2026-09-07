import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Explicit formal fixtures test call-by-name at the native compiler boundary.
@TLAModel
private struct UnusedOperatorArguments {
    static var spec: TLASpec {
        TLASpec("UnusedOperatorArguments") {
            let result = Var<Int>("result")
            Variable(result, 0)
            FormalDefinition("Ignore", parameters: [.value("unused")], body: 7)
            SwiftTLA.Action("formal") {
                result.becomes(FormalCall("Ignore", Expr<Int>(1) / 0))
            }
            SwiftTLA.Action("local") {
                result.becomes(Expr<Int>(StateExpr.letIn([
                    LocalOperator("IgnoreLocal", parameters: ["unused"], body: 9)
                ], StateExpr.operatorApplication(
                    .reference("IgnoreLocal", arity: 1), [.value(StateExpr.variable("result") / 0)]
                ))))
            }
        }
    }
}

@TLAModel
private struct ExhaustedOperatorDepth {
    static var spec: TLASpec {
        TLASpec("ExhaustedOperatorDepth") {
            let result = Var<Int>("result")
            Variable(result, 0)
            FormalDefinition("Loop", parameters: [], body: StateExpr.operatorApplication(.reference("Loop", arity: 0), []))
            SwiftTLA.Action("loop") {
                result.becomes(FormalCall("Loop"))
            }
        }
    }
}

@TLAModel
private struct NestedLambdaCallDepth {
    static var spec: TLASpec {
        TLASpec("NestedLambdaCallDepth") {
            let result = Var<Int>("result")
            Variable(result, 9)
            FormalDefinition("CountDown", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: 0,
                else: StateExpr.operatorApplication(
                    .lambda(FormalLambda(parameters: ["next"], body: StateExpr.operatorApplication(
                        .reference("CountDown", arity: 1), [.value(StateExpr.variable("next"))]
                    ))),
                    [.value(StateExpr.variable("remaining") - 1)]
                )
            ))
            SwiftTLA.Action("countDown") {
                result.becomes(FormalCall("CountDown", 2050))
            }
        }
    }
}

@Suite struct NativeOperatorEvaluationTests {
    @Test("formal and local operators do not evaluate unused invalid arguments")
    func unusedArgumentsRemainLazy() throws {
        let compilation = try UnusedOperatorArguments.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        var formalMachine = try UnusedOperatorArguments.makeMachine()
        var localMachine = try UnusedOperatorArguments.makeMachine()
        let formalAction = try #require(compilation.layout.testActionID(named: "formal"))
        let localAction = try #require(compilation.layout.testActionID(named: "local"))
        let formalSuccessor = try #require(try runtime.successors(for: formalAction, from: initial).first)
        let localSuccessor = try #require(try runtime.successors(for: localAction, from: initial).first)
        #expect(try formalMachine.send(.formal).after.result == 7)
        #expect(try localMachine.send(.local).after.result == 9)
        #expect(try formalSuccessor.state.value(for: result) == .integer(formalMachine.state.result))
        #expect(try localSuccessor.state.value(for: result) == .integer(localMachine.state.result))
    }

    @Test("native recursion stops at the shared formal limit without committing state")
    func recursionLimitIsTransactional() throws {
        let compilation = try ExhaustedOperatorDepth.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "loop"))
        let limit = _NativeMachineOperations.maximumRecursiveDepth
        #expect(throws: EvalError.recursionDepthExceeded(limit)) {
            try runtime.successors(for: action, from: initial)
        }
        var machine = try ExhaustedOperatorDepth.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.recursionDepthExceeded(limit)) {
            try machine.send(.loop)
        }
        #expect(machine.state == before)
    }

    @Test("Lambda applications consume the same recursion budget as named calls")
    func lambdaFramesCountTowardLimit() throws {
        let compilation = try NestedLambdaCallDepth.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "countDown"))
        let limit = _NativeMachineOperations.maximumRecursiveDepth
        // 2,050 named calls fit; the interleaved lambda calls exceed the limit.
        #expect(2050 < limit && 2050 * 2 > limit)
        #expect(throws: EvalError.recursionDepthExceeded(limit)) {
            try runtime.successors(for: action, from: initial)
        }
        var machine = try NestedLambdaCallDepth.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.recursionDepthExceeded(limit)) {
            try machine.send(.countDown)
        }
        #expect(machine.state == before)
    }
}
