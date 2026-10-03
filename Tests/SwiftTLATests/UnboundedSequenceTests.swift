import Testing
@testable import SwiftTLA

struct UnboundedSequenceTests {
    @Test("Selected sequence inputs have no artificial length bound")
    func selectedInputAndExport() throws {
        for input in [[], [1, 2], Array(repeating: 2, count: 10_000)] {
            var machine = try UnboundedSequenceModel.makeMachine(.init(sequence: input))
            #expect(machine.state.sequence == input)
            #expect(try machine.send(.append).after.sequence == input + [1])
        }
        #expect(throws: GeneratedMachineError.invalidInitialState) {
            try UnboundedSequenceModel.makeMachine(.init(sequence: [1, 3]))
        }
        #expect(throws: NativeMachineEvaluationError.nonEnumerableSequenceDomain) {
            try UnboundedSequenceModel.makeMachine()
        }
        let bundle = try UnboundedSequenceModel.spec.compile().render().tlaBundle
        #expect(bundle.tla.contains("Seq({1, 2})"))
    }

    @Test("Sequence membership does not enumerate the sequence universe")
    func membershipAndEnumeration() throws {
        let domain = Sequences(of: Set<Int>([1, 2]))
        for input in [[], [1, 2], Array(repeating: 1, count: 100)] {
            #expect(try evaluateClosed(domain.contains(input).stateExpr) == .bool(true))
        }
        #expect(try evaluateClosed(domain.contains([3]).stateExpr) == .bool(false))
        #expect(throws: EvalError.nonEnumerableSequenceDomain) {
            try evaluateClosed(domain.stateExpr)
        }
        #expect(try evaluateClosed(Sequences(of: Set<Int>([])).stateExpr) == .set([.tuple([])]))
    }
}
