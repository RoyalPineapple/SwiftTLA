import Testing
import SwiftTLA

struct GeneratedSavedValueSwapTests {
    @Test("Saved values preserve a swap in an ordered atomic step")
    func generatedMachineSwapsValues() throws {
        var machine = try GeneratedSavedValueSwap.makeMachine()

        let transitionBefore = machine.state
        try machine.send(.swap)

        #expect(transitionBefore.left == 1)
        #expect(transitionBefore.right == 2)
        #expect(machine.state.left == 2)
        #expect(machine.state.right == 1)
    }

}
