import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct IncreasingSelection {
    static var spec: TLASpec {
        #spec("IncreasingSelection") { scope in
            let current = scope.sharedVar("position", initial: 0)
            SwiftTLA.Action("advance") {
                let previous = current.expr
                current.becomes(Select(from: SetExpr<Int>.literal(1, 2, 3)) { candidate in
                    candidate.expr > previous
                })
            }
        }
    }
}

struct TypedSelectionTests {
    @Test("A formal choice reads current state in native and formal execution")
    func selectionUsesCurrentState() throws {
        let compilation = try IncreasingSelection.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(runtime.initialStates().first)
        var native = try IncreasingSelection.makeMachine()
        let current = try #require(compilation.layout.variables.first?.id)
        for expected in 1...3 {
            let successors = try runtime.successors(from: formal)
            try #require(successors.count == 1)
            formal = try #require(successors.first?.state)
            #expect(try formal.value(for: current) == .integer(expected))
            #expect(try native.enabledActions() == [.advance])
            _ = try native.send(.advance)
            #expect(native.state.position == expected)
        }
        #expect(throws: EvalError.noSatisfyingChoice) { try runtime.successors(from: formal) }
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) { _ = try native.send(.advance) }
        #expect(native.state.position == 3)
    }

    @Test("An empty matching domain fails when the choice is evaluated")
    func missingSelectionFailsDuringEvaluation() throws {
        let choice = Select(from: SetExpr<Int>.literal(1)) { _ in false }
        #expect(throws: EvalError.noSatisfyingChoice) { try evaluateClosed(choice.stateExpr) }
    }
}
