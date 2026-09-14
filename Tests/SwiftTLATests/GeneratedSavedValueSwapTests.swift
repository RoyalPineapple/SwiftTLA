import Testing
import SwiftTLA

struct GeneratedSavedValueSwapTests {
    @Test("Saved values preserve a swap in an ordered atomic step")
    func generatedMachineSwapsValues() throws {
        var machine = try GeneratedSavedValueSwap.makeMachine()

        let transition = try machine.send(.swap)

        #expect(transition.before.left == 1)
        #expect(transition.before.right == 2)
        #expect(transition.after.left == 2)
        #expect(transition.after.right == 1)
        #expect(machine.state == transition.after)
    }

}
