import Foundation
import Testing
@testable import UpstreamParity

struct CompactTLCGraphEventTests {
    private let runID = "00000000-0000-4000-8000-000000000001"

    @Test("ordered bridge events retain complete state and labeled transition data")
    func parsesCompleteTransition() throws {
        let line = #"{"schema":"swifttla.tlc.graph-events","version":4,"type":"transition","callback":"writeState.action","seq":2,"runId":"00000000-0000-4000-8000-000000000001","caseId":"fixture","source":{"fingerprint":"1","level":1},"target":{"fingerprint":"2","level":2,"bindings":[{"ordinal":0,"name":"x","tla":"1"}]},"action":{"name":"Next","location":"<Next line 1>","named":true},"resolvedActions":[{"name":"Next","location":"<Next line 1>","named":true}],"stateFlags":{"raw":0,"seen":false,"notInModel":false},"visualization":"none","predicateLocation":null,"reachable":"reachable"}"#
        let event = try CompactTLCGraphEvent.parse(Data(line.utf8), caseID: "fixture",
            expectedRunID: runID, sequence: 2)
        guard case .transition(let source, let target, let seen, let excluded,
            let flags, let actions, let predicate, let reachable) = event.payload else {
            Issue.record("Expected a transition")
            return
        }
        #expect(source == 1)
        #expect(target.fingerprint == 2)
        #expect(target.bindings?.first?.name == "x")
        #expect(target.bindings?.first?.tla == "1")
        #expect(!seen && !excluded && flags == 0)
        #expect(actions.count == 1 && actions[0].name == "Next")
        #expect(actions[0].location == "<Next line 1>")
        #expect(predicate == nil && reachable == "reachable")
    }

    @Test("duplicate bridge fields cannot override a validated transition")
    func rejectsDuplicateFields() {
        let line = #"{"schema":"swifttla.tlc.graph-events","version":4,"type":"header","callback":"writer.header","seq":0,"runId":"00000000-0000-4000-8000-000000000001","caseId":"fixture","caseId":"other"}"#
        #expect(throws: CompactTLCGraphEvent.Error.self) {
            try CompactTLCGraphEvent.parse(Data(line.utf8), caseID: "fixture",
                expectedRunID: nil, sequence: 0)
        }
    }
}
