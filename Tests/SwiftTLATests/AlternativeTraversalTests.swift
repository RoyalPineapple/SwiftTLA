import SwiftTLA
import Testing

@Suite("Alternative traversal")
struct AlternativeTraversalTests {
    @Test("Successful updates survive a failing alternative")
    func mixedOutcomes() {
        var emitted: [Int] = []
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.visitAlternatives([0, 1], emit: { emitted.append($0) }) { alternative, emit in
                try emit(alternative)
                if alternative == 0 { throw NativeMachineEvaluationError.divisionByZero }
            }
        }
        #expect(emitted == [0, 1])
    }

    @Test("An output callback error is not treated as a model failure")
    func callbackFailure() {
        var visited: [Int] = []
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try _NativeMachineOperations.visitAlternatives([0, 1], emit: { (_: Int) in
                throw NativeMachineEvaluationError.noMatchingCase
            }) { alternative, emit in
                visited.append(alternative)
                try emit(alternative)
                if alternative == 0 { throw NativeMachineEvaluationError.divisionByZero }
            }
        }
        #expect(visited == [0])
    }
}
