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
            FormalDefinition("Every", parameters: [.value("domain"), .value("unused")], body: StateExpr.forAll(
                StateExpr.variable("domain"), "item",
                StateExpr.variable("item") == StateExpr.variable("unused")
            ))
            FormalDefinition("Map", parameters: [.value("domain"), .value("unused")], body: StateExpr.setMap(
                StateExpr.variable("unused"), "item", StateExpr.variable("domain")
            ))
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
            SwiftTLA.Action("emptyDomain") {
                result.becomes(Expr<Int>(StateExpr.if(
                    StateExpr.operatorApplication(.reference("Every", arity: 2), [
                        .value(StateExpr.integerRange(1, 0)),
                        .value(StateExpr.variable("result") / 0)
                    ]),
                    then: 7,
                    else: 9
                )))
            }
            SwiftTLA.Action("emptyMapping") {
                result.becomes(Expr<Int>(StateExpr.operatorApplication(
                    .reference("Map", arity: 2), [
                        .value(StateExpr.integerRange(1, 0)),
                        .value(StateExpr.variable("result") / 0)
                    ]
                ).cardinality))
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
            SwiftTLA.Action("complete") {
                result.becomes(FormalCall("CountDown", 1000))
            }
        }
    }
}

@TLAModel
private struct TailArgumentFailureOrder {
    static var spec: TLASpec {
        TLASpec("TailArgumentFailureOrder") {
            let result = Var<Int>("result")
            Variable(result, 9)
            FormalDefinition("CountDown", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: 0,
                else: StateExpr.operatorApplication(.reference("CountDown", arity: 1), [.value(
                    StateExpr.if(
                        StateExpr.variable("remaining") == 1,
                        then: StateExpr.variable("remaining") / 0,
                        else: StateExpr.variable("remaining") - 1
                    )
                )])
            ))
            SwiftTLA.Action("atLimit") {
                result.becomes(FormalCall("CountDown", 4096))
            }
            SwiftTLA.Action("belowLimit") {
                result.becomes(FormalCall("CountDown", 4095))
            }
            FormalDefinition("FailBeforeRead", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("result") / 0 == StateExpr.variable("remaining"),
                then: 0,
                else: StateExpr.operatorApplication(.reference("FailBeforeRead", arity: 1), [.value(
                    StateExpr.variable("remaining")
                )])
            ))
            SwiftTLA.Action("earlyFailure") {
                result.becomes(FormalCall("FailBeforeRead", Expr<Int>(9_223_372_036_854_775_807) + 1))
            }
            FormalDefinition("Reverse", parameters: [.value("first"), .value("second")], body:
                StateExpr.variable("second") - StateExpr.variable("first")
            )
            SwiftTLA.Action("reverseFailure") {
                result.becomes(FormalCall("Reverse",
                    Expr<Int>(9_223_372_036_854_775_807) + 1,
                    Expr<Int>(1) / 0
                ))
            }
        }
    }
}

@TLAModel
private struct EvaluatedArgumentReuse {
    static var spec: TLASpec {
        TLASpec("EvaluatedArgumentReuse") {
            let result = Var<Int>("result")
            Variable(result, 9)
            FormalDefinition("Start", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: 0,
                else: StateExpr.operatorApplication(.reference("Finish", arity: 1), [.value(
                    StateExpr.operatorApplication(.reference("DeepValue", arity: 1), [.value(4093)])
                )])
            ))
            FormalDefinition("Finish", parameters: [.value("value")], body: StateExpr.if(
                StateExpr.variable("value") > 0,
                then: StateExpr.operatorApplication(.reference("Start", arity: 1), [.value(
                    StateExpr.variable("value") - 1
                )]),
                else: 0
            ))
            FormalDefinition("DeepValue", parameters: [.value("remaining")], body: StateExpr.if(
                StateExpr.variable("remaining") == 0,
                then: 1,
                else: StateExpr.operatorApplication(.reference("DeepValue", arity: 1), [.value(
                    StateExpr.variable("remaining") - 1
                )])
            ))
            SwiftTLA.Action("finish") {
                result.becomes(FormalCall("Start", 1))
            }
            FormalDefinition("UseTwice", parameters: [.value("value")], body: StateExpr.if(
                StateExpr.variable("value") > 0,
                then: StateExpr.operatorApplication(.reference("ReadLater", arity: 1), [.value(
                    StateExpr.variable("value")
                )]),
                else: 0
            ))
            FormalDefinition("ReadLater", parameters: [.value("value")], body: StateExpr.variable("value") - 1)
            SwiftTLA.Action("reuseOrdinary") {
                result.becomes(FormalCall("UseTwice", Expr<Int>(StateExpr.operatorApplication(
                    .reference("DeepValue", arity: 1), [.value(4094)]
                ))))
            }
            SwiftTLA.Action("reuseLet") {
                result.becomes(Expr<Int>(StateExpr.letValue(
                    "once",
                    StateExpr.operatorApplication(.reference("DeepValue", arity: 1), [.value(4095)]),
                    StateExpr.if(
                        StateExpr.variable("once") > 0,
                        then: StateExpr.operatorApplication(.reference("ReadLater", arity: 1), [.value(
                            StateExpr.variable("once")
                        )]),
                        else: 0
                    )
                )))
            }
        }
    }
}

@Suite struct NativeOperatorEvaluationTests {
    @Test("an empty mapping domain leaves its body argument unevaluated")
    func emptyMappingDoesNotForceBodyArguments() throws {
        let compilation = try UnusedOperatorArguments.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "emptyMapping"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try UnusedOperatorArguments.makeMachine()
        #expect(try successor.state.value(for: result) == .integer(0))
        #expect(try machine.send(.emptyMapping).after.result == 0)
    }

    @Test("an empty quantifier domain leaves its body argument unevaluated")
    func emptyDomainDoesNotForceBodyArguments() throws {
        let compilation = try UnusedOperatorArguments.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "emptyDomain"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try UnusedOperatorArguments.makeMachine()
        #expect(try successor.state.value(for: result) == .integer(7))
        #expect(try machine.send(.emptyDomain).after.result == 7)
    }

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

    @Test("deep calls through lambdas return the same value as formal execution")
    func deepLambdaCallsComplete() throws {
        let compilation = try NestedLambdaCallDepth.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "complete"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try NestedLambdaCallDepth.makeMachine()
        #expect(try machine.send(.complete).after.result == 0)
        #expect(try successor.state.value(for: result) == .integer(machine.state.result))
    }

    @Test("the call budget is checked before evaluating a deferred tail argument")
    func tailArgumentsPreserveFailureOrder() throws {
        let compilation = try TailArgumentFailureOrder.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let atLimit = try #require(compilation.layout.testActionID(named: "atLimit"))
        let belowLimit = try #require(compilation.layout.testActionID(named: "belowLimit"))
        let limit = _NativeMachineOperations.maximumRecursiveDepth
        #expect(throws: EvalError.recursionDepthExceeded(limit)) {
            try runtime.successors(for: atLimit, from: initial)
        }
        #expect(throws: EvalError.divisionByZero) {
            try runtime.successors(for: belowLimit, from: initial)
        }
        var machine = try TailArgumentFailureOrder.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.recursionDepthExceeded(limit)) {
            try machine.send(.atLimit)
        }
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.belowLimit)
        }
        #expect(machine.state == before)
    }

    @Test("an evaluated tail argument is reused after entering a deeper call")
    func evaluatedTailArgumentsAreReused() throws {
        let compilation = try EvaluatedArgumentReuse.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "finish"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try EvaluatedArgumentReuse.makeMachine()
        #expect(try machine.send(.finish).after.result == 0)
        #expect(try successor.state.value(for: result) == .integer(machine.state.result))
    }

    @Test("ordinary calls reuse an evaluated argument in a deeper callee")
    func ordinaryCallsReuseEvaluatedArguments() throws {
        let compilation = try EvaluatedArgumentReuse.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "reuseOrdinary"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try EvaluatedArgumentReuse.makeMachine()
        #expect(try successor.state.value(for: result) == .integer(0))
        #expect(try machine.send(.reuseOrdinary).after.result == 0)
    }

    @Test("LET values reuse their evaluated result inside a deeper callee")
    func letValuesReuseEvaluatedResults() throws {
        let compilation = try EvaluatedArgumentReuse.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "reuseLet"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try EvaluatedArgumentReuse.makeMachine()
        #expect(try successor.state.value(for: result) == .integer(0))
        #expect(try machine.send(.reuseLet).after.result == 0)
    }

    @Test("an earlier body failure does not force a later argument")
    func bodyFailurePrecedesArgumentFailure() throws {
        let compilation = try TailArgumentFailureOrder.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "earlyFailure"))
        #expect(throws: EvalError.divisionByZero) {
            try runtime.successors(for: action, from: initial)
        }
        var machine = try TailArgumentFailureOrder.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.earlyFailure)
        }
        #expect(machine.state == before)
    }

    @Test("arguments are evaluated in first-read order rather than declaration order")
    func firstReadDeterminesArgumentFailure() throws {
        let compilation = try TailArgumentFailureOrder.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "reverseFailure"))
        #expect(throws: EvalError.divisionByZero) {
            try runtime.successors(for: action, from: initial)
        }
        var machine = try TailArgumentFailureOrder.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.reverseFailure)
        }
        #expect(machine.state == before)
    }
}
