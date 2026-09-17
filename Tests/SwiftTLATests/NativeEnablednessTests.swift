import Testing
@testable import SwiftTLA

struct NativeEnablednessTests {
    @Test("Native action guards evaluate enabledness only when demanded")
    func actionGuards() throws {
        let machine = try GuardedEnabledness.makeMachine()
        #expect(try machine.successors(for: .blocked).isEmpty)
        let next = try machine.successors(for: .guardedStay)
        #expect(next.count == 1)
        #expect(next.first?.state == machine.state)
        #expect(throws: (any Error).self) { try machine.successors(for: .divide) }
    }

    @Test("State predicates preserve short-circuit enabledness and demanded failures")
    func statePredicates() throws {
        let machine = try GuardedEnabledness.makeMachine()
        #expect(try machine.satisfiesStateConstraint())
        #expect(try machine.violatedInvariants(checking: [.guardedInvariant]).isEmpty)
        #expect(try machine.matchedReachabilityProperties(checking: [.guardedReachable]) == [.guardedReachable])
        #expect(throws: (any Error).self) { try machine.violatedInvariants(checking: [.demandedInvariant]) }
        #expect(throws: (any Error).self) { try machine.matchedReachabilityProperties(checking: [.demandedReachable]) }
    }
}
