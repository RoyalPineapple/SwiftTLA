import Testing
import SwiftTLA

@Suite struct NativeSupportBindingTests {
    @Test("Generated arithmetic binds library support, not a model's same-named helper")
    func modelHelperCannotReplaceCheckedAddition() throws {
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
