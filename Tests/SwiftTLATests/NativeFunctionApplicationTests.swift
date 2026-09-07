import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct SequenceFunctionApplications {
    static var spec: TLASpec {
        TLASpec("SequenceFunctionApplications") {
            let number = Var<Int>("number")
            let flag = Var<Bool>("flag")
            Variable(number, 0)
            Variable(flag, false)
            SwiftTLA.Action("array") {
                number.becomes(Expr<Int>(StateExpr.tuple([10, 20]).applying(2)))
            }
            SwiftTLA.Action("pair") {
                number.becomes(Expr<Int>(StateExpr.tuple([7.stateExpr, true.stateExpr]).applying(1)))
                flag.becomes(Expr<Bool>(StateExpr.tuple([7.stateExpr, true.stateExpr]).applying(2)))
            }
            SwiftTLA.Action("argumentError") {
                number.becomes(Expr<Int>(
                    StateExpr.tuple([Expr<Int>(1) / 0]).applying(StateExpr.negate(-9223372036854775808))
                ))
            }
        }
    }
}

@Suite struct NativeFunctionApplicationTests {
    @Test("Homogeneous and heterogeneous tuples retain one-based function application")
    func sequenceApplicationsMatchFormalSuccessors() throws {
        let compilation = try SequenceFunctionApplications.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let number = try #require(compilation.layout.testVariableID(named: "number"))
        let flag = try #require(compilation.layout.testVariableID(named: "flag"))
        let cases: [(String, SequenceFunctionApplications.Action, Int, Bool)] = [
            ("array", .array, 20, false), ("pair", .pair, 7, true)
        ]
        for (name, action, expectedNumber, expectedFlag) in cases {
            let id = try #require(compilation.layout.testActionID(named: name))
            let successors = try runtime.successors(for: id, from: initial)
            #expect(successors.count == 1)
            let successor = try #require(successors.first)
            var machine = try SequenceFunctionApplications.makeMachine()
            let after = try machine.send(action).after
            #expect(after.number == expectedNumber)
            #expect(after.flag == expectedFlag)
            #expect(try successor.state.value(for: number) == .integer(after.number))
            #expect(try successor.state.value(for: flag) == .boolean(after.flag))
        }
    }

    @Test("Function arguments fail before tuple contents are evaluated")
    func argumentFailurePrecedesTupleFailure() throws {
        let compilation = try SequenceFunctionApplications.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let id = try #require(compilation.layout.testActionID(named: "argumentError"))
        #expect(throws: EvalError.integerOverflow(.negation, operands: [Int.min])) {
            try runtime.successors(for: id, from: initial)
        }
        var machine = try SequenceFunctionApplications.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.negation, operands: [Int.min])) {
            try machine.send(.argumentError)
        }
        #expect(machine.state == before)
    }
}
