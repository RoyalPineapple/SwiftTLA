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

        let initial = try GeneratedDuplicateSuccessor.makeMachine()
        var context = CheckingContext(registers: try initial.initialCheckingRegisters())
        let listed = try initial.successors(checking: &context)
        var visited: [GeneratedDuplicateSuccessor.Snapshot] = []
        let found = try initial.visitSuccessors(checking: &context) { _, successor in
            visited.append(successor.snapshot)
            return true
        }
        #expect(found)
        #expect(listed.count == 1)
        #expect(visited == [listed[0].machine.snapshot])
        #expect(visited[0].state == transition.after)
    }
}
