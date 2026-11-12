import Testing
import SwiftTLA

@Suite struct NativeSupportBindingTests {
    @Test("Generated initial collection and arithmetic retain library behavior under caller overloads")
    func modelHelperCannotReplaceCheckedAddition() throws {
        let initial = try NativeSupportBindingModel.initialOutcomes()
        #expect(initial.states.count == 1)
        #expect(initial.failures.isEmpty)
        var machine = try NativeSupportBindingModel.makeMachine()
        #expect(machine.state.seed == 0 && machine.state.count == 1)
        #expect(try machine.send(.advance).after.count == 2)
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [2, Int.max])) {
            try machine.send(.overflow)
        }
        #expect(machine.snapshot == before)
    }
}
