import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct InjectiveSequenceExecution {
    enum Step: String, CaseIterable { case append }
    static var spec: TLASpec {
        #spec("InjectiveSequenceExecution") {
            Import(FunctionsModule.module)
            Algorithm("InjectiveSequenceExecution", scoped: { scope in
                let history = scope.sharedVar("history", initial: TupleExpr<Int>.literal(0))
                Do(Step.append) {
                    Assign(history, to: history.expr.concatenating(
                        InjectiveSequence(from: SetExpr<Int>.literal(1, 2))
                    ))
                }
            })
        }
    }
}

// Formal fixture exposes an integer function whose domain is not a sequence.
@TLAModel
private struct InvalidSequenceFunctionExecution {
    static var spec: TLASpec {
        TLASpec("InvalidSequenceFunctionExecution") {
            let result = Var<Int>("result")
            Variable(result, 0)
            SwiftTLA.Action("length") {
                result.becomes(Expr<Int>(Function<Int, Int>.literal((2, 7)).stateExpr.count))
            }
            SwiftTLA.Action("indexFailure") {
                result.becomes(Expr<TupleExpr<Int>>(
                    Function<Int, Int>.literal((2, 7)).stateExpr
                ).at(Expr<Int>(1) / 0))
            }
        }
    }
}

@Suite("Native sequence operations accept exactly one-based function domains")
struct NativeSequenceFunctionTests {
    @Test("Injective function choices concatenate as sequences without changing function identity")
    func injectiveSequenceMatchesFormalSuccessor() throws {
        let compilation = try InjectiveSequenceExecution.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "append"))
        let history = try #require(compilation.layout.testVariableID(named: "history"))
        let next = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try InjectiveSequenceExecution.makeMachine()
        _ = try machine.send(.append)
        #expect(machine.state.history == [0, 1, 2])
        #expect(try next.state.value(for: history).rendered(using: compilation.layout)
            == .tuple(machine.state.history.map(TLAValue.int)))
    }

    @Test("Integer functions require every key from one through their count")
    func malformedDomainsAreRejected() throws {
        #expect(try _NativeMachineOperations.sequenceElements([2: 20, 1: 10]) == [10, 20])
        #expect(try _NativeMachineOperations.sequenceElements([Int: Int]()).isEmpty)
        let domains: [[Int: Int]] = [[0: 7], [2: 7], [1: 7, 3: 9], [Int.min: 7]]
        for function in domains {
            #expect(throws: NativeMachineEvaluationError.invalidSequenceDomain(keys: function.keys.sorted())) {
                _ = try _NativeMachineOperations.sequenceElements(function)
            }
            let formal = TLAValue.function(Dictionary(uniqueKeysWithValues: function.map { (.int($0.key), .int($0.value)) }))
            #expect(throws: EvalError.expected(.sequence, actual: [CompiledValue(formal: formal)])) {
                _ = try compiledValue(.tupleLength(.value(formal)))
            }
        }
        var machine = try InvalidSequenceFunctionExecution.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.invalidSequenceDomain(keys: [2])) {
            _ = try machine.send(.length)
        }
        #expect(machine.state == before)
    }

    @Test("Index expression errors occur before validating the sequence function domain")
    func sequenceValidationPreservesOperandOrder() throws {
        var machine = try InvalidSequenceFunctionExecution.makeMachine()
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            _ = try machine.send(.indexFailure)
        }
        #expect(machine.state.result == 0)
    }
}
