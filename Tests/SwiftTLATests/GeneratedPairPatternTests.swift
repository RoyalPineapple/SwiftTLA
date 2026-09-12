@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedPairPatternTests {
    @Test("a generated machine rejects an action with multiple valid successors")
    func generatedMachineRejectsAmbiguousPairSelection() throws {
        var machine = try GeneratedPairPattern.makeMachine()
        do {
            _ = try machine.send(.choose)
            Issue.record("Expected ambiguous action")
        } catch GeneratedMachineError.ambiguousAction {
        } catch {
            Issue.record("Expected ambiguous action, received \(error)")
        }
        #expect(machine.state.selected == 0)
        let successors = try machine.successors(for: .choose)
        #expect(Set(successors.map { $0.state.selected }) == [1, 2])
        for successor in successors {
            #expect(try successor.enabledActions().isEmpty)
            #expect(try successor.successors(for: .choose).isEmpty)
        }
        #expect(try machine.isEnabled(.choose))
    }
}
