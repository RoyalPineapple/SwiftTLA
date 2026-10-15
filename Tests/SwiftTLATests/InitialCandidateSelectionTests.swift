@testable import SwiftTLA
import Testing

@Suite("Initial candidate selection")
struct InitialCandidateSelectionTests {
    @Test("Enumeration keeps every candidate and does not test membership")
    func enumeration() throws {
        var membershipCalls = 0
        let values = try _NativeMachineOperations.initialCandidates(
            selecting: Optional<Int>.none,
            enumerate: { [2, 1, 2] },
            contains: { _ in
                membershipCalls += 1
                return false
            })
        #expect(values == [2, 1, 2])
        #expect(membershipCalls == 0)
    }

    @Test("A selected member is accepted without enumerating the domain")
    func selectedMember() throws {
        var enumerationCalls = 0
        let values = try _NativeMachineOperations.initialCandidates(
            selecting: 7,
            enumerate: {
                enumerationCalls += 1
                return [1, 2]
            },
            contains: { $0 == 7 })
        #expect(values == [7])
        #expect(enumerationCalls == 0)
    }

    @Test("A selected nonmember is excluded")
    func selectedNonmember() throws {
        let values = try _NativeMachineOperations.initialCandidates(
            selecting: 7,
            enumerate: { [7] },
            contains: { _ in false })
        #expect(values.isEmpty)
    }

    @Test("A membership evaluation failure is preserved")
    func membershipFailure() {
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.initialCandidates(
                selecting: 7,
                enumerate: { [7] },
                contains: { _ in throw NativeMachineEvaluationError.divisionByZero })
        }
    }
}
