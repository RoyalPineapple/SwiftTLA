@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedSimultaneousSwapTests {
    @Test("generated updates read one old state and commit together")
    func generatedMachineSwapsValues() throws {
        var machine = try GeneratedSimultaneousSwap.makeMachine()

        let transition = try machine.send(.swap)

        #expect(transition.before.left == 1)
        #expect(transition.before.right == 2)
        #expect(transition.after.left == 2)
        #expect(transition.after.right == 1)
        #expect(machine.state == transition.after)
    }

}
