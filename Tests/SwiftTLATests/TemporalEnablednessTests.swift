import Testing
@testable import SwiftTLA

struct TemporalEnablednessTests {
    @Test("Temporal guards skip unused enabledness reads but demanded reads still fail")
    func respectsGuardEvaluation() throws {
        let machine = try GuardedTemporalEnabledness.makeMachine()
        let properties = try machine.temporalProperties()
        for property: GuardedTemporalEnabledness.Property in [.stutter, .guarded, .alternative] {
            guard case .always(let predicate) = try #require(properties[property]) else {
                Issue.record("Expected an always predicate")
                continue
            }
            #expect(try predicate(machine.snapshot, machine.snapshot))
        }
        guard case .always(let demanded) = try #require(properties[.demanded]) else {
            Issue.record("Expected an always predicate")
            return
        }
        #expect(throws: (any Error).self) { try demanded(machine.snapshot, machine.snapshot) }
    }
}
