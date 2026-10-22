import Foundation
import Testing
@testable import SwiftTLA

@Suite("Checked view kind mismatch")
struct CheckedViewKindMismatchTests {
    @Test("A scalar-to-record checked view reports a matched failure without a successor")
    func scalarToRecordFailure() throws {
        var machine = try IncompatibleCheckedRecordView.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.inspect)
        }
        #expect(machine.snapshot == before)

        let rendered = try IncompatibleCheckedRecordView.render()
        #expect(rendered.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let source = rendered.tlaBundle.root.tla
        #expect(!source.contains("DOMAIN count"))
        #expect(source.contains("__SwiftTLANoMatchingCaseFailure0"))
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/IncompatibleCheckedRecordView.tla")
            .standardizedFileURL
        #expect(source == (try String(contentsOf: proofInput, encoding: .utf8)))
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }
}
