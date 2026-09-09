import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct OrderedSequenceRemoval {
    enum Step: String, CaseIterable { case remove }
    static var spec: TLASpec {
        #spec("OrderedSequenceRemoval") {
            Algorithm("OrderedSequenceRemoval", scoped: { scope in
                let items = scope.sharedVar("items", initial: TupleExpr<Int>.literal(3, 2, 2, 1))
                Do(Step.remove) {
                    Assign(items, to: items.expr.removing(at: 2))
                    Goto(Step.remove)
                }
            })
        }
    }
}

// A formal fixture exercises malformed function domains at the sequence boundary.
@TLAModel
private struct SequenceRemovalFailure {
    static var spec: TLASpec {
        TLASpec("SequenceRemovalFailure") {
            let items = Var<TupleExpr<Int>>("items")
            Variable(items, TupleExpr<Int>.literal(7))
            SwiftTLA.Action("remove") {
                items.becomes(Expr<TupleExpr<Int>>(
                    StateExpr.functionLiteral(StateExpr.set([2]), "key", 7)
                ).removing(at: Expr<Int>(1) / 0))
            }
        }
    }
}

@Suite("Native sequence removal preserves ordered occurrences")
struct NativeSequenceRemovalTests {
    @Test("Removing one occurrence preserves every other position")
    func removalMatchesFormalExecution() throws {
        let compilation = try OrderedSequenceRemoval.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().first)
        let items = try #require(compilation.layout.testVariableID(named: "items"))
        let action = try #require(compilation.layout.testActionID(named: "remove"))
        var machine = try OrderedSequenceRemoval.makeMachine()
        for expected in [[3, 2, 1], [3, 1], [3]] {
            formal = try #require(try runtime.successors(for: action, from: formal).first).state
            _ = try machine.send(.remove)
            #expect(machine.state.items == expected)
            #expect(try formal.value(for: items) == .tuple(expected.map(CompiledValue.integer)))
        }
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 2, count: 1)) {
            _ = try machine.send(.remove)
        }
        #expect(machine.state == before)
    }

    @Test("Indices are one-based and checked before subtraction")
    func checkedBounds() throws {
        for sequence in [[], [7], [3, 2, 2, 1]] {
            for index in [Int.min, -1, 0, 1, 2, 4, 5, Int.max] {
                let expression = StateExpr.tupleRemoving(.value(.tuple(sequence.map(TLAValue.int))), .int(index))
                if index >= 1 && index <= sequence.count {
                    let native = try _NativeMachineOperations.sequenceRemoving(sequence, at: index)
                    #expect(try evaluateClosed(expression) == .tuple(native.map(TLAValue.int)))
                } else {
                    #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: index, count: sequence.count)) {
                        _ = try _NativeMachineOperations.sequenceRemoving(sequence, at: index)
                    }
                    #expect(throws: EvalError.indexOutOfBounds(index, sequence.count)) {
                        _ = try evaluateClosed(expression)
                    }
                }
            }
        }
    }

    @Test("Index expression failure precedes malformed sequence domain validation")
    func indexFailureOrder() throws {
        let expression = StateExpr.tupleRemoving(
            .value(.function([.int(2): .int(7)])), .integerDivide(.int(1), .int(0)))
        #expect(throws: EvalError.divisionByZero) { _ = try evaluateClosed(expression) }
        var machine = try SequenceRemovalFailure.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.divisionByZero) { _ = try machine.send(.remove) }
        #expect(machine.state == before)
    }
}
