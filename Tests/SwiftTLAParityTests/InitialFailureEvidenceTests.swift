import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite("Selected initial failure evidence")
struct InitialFailureEvidenceTests {
    @Test("A failure-only initializer compares the exact selected payload without a graph")
    func comparesSelectedFailure() throws {
        let native = try CheckedAdditionPrefixInitialModel.initialOutcomes()
        #expect(native.states.isEmpty)
        let expected = CanonicalValue.record([
            "site": .integer(3), "kind": .string("integerOverflow.addition"),
            "operands": .tuple([.integer(3), .integer(Int.max)])
        ])
        let selected = try InitialFailureEvidence.compare(
            site: native.firstFailureInitializerOrdinal, reason: native.firstFailure,
            successfulInitialStates: native.states.count, verdict: .violated,
            printed: [expected])
        #expect(selected.site == 3)
        #expect(selected.operands == [3, Int.max])

        let wrong = CanonicalValue.record([
            "site": .integer(3), "kind": .string("integerOverflow.addition"),
            "operands": .tuple([.integer(3), .integer(Int.max - 1)])
        ])
        #expect(throws: InitialFailureEvidenceError.payloadMismatch) {
            try InitialFailureEvidence.compare(site: native.firstFailureInitializerOrdinal,
                reason: native.firstFailure, successfulInitialStates: 0,
                verdict: .violated, printed: [wrong])
        }
        #expect(throws: InitialFailureEvidenceError.unsupportedNativeOutcome) {
            try InitialFailureEvidence.compare(site: native.firstFailureInitializerOrdinal,
                reason: native.firstFailure, successfulInitialStates: 1,
                verdict: .violated, printed: [expected])
        }
    }
}
