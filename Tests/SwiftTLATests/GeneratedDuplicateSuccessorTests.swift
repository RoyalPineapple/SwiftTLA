@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedDuplicateSuccessorTests {
    @Test("a generated machine coalesces identical successors for one action")
    func generatedMachineSendsOneSemanticTransition() throws {
        var machine = try GeneratedDuplicateSuccessor.makeMachine()

        let transition = try machine.send(.choose)

        #expect(transition.before.selected == 0)
        #expect(transition.after.selected == 1)
        #expect(machine.state == transition.after)
    }
}
