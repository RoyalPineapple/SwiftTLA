import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct UpstreamTLCParityCacheTests {
    @Test("upstream evidence is bound to both module inputs and the exploration limit")
    func cacheKeyChangesWithReferenceOrLimit() throws {
        let scenario = try #require(modelValidationScenarios().first).scenario
        let rendered = try scenario.render()
        let pin = try testReferencePin()
        func reference(_ value: Int) -> TLAModuleBundle {
            .external(root: .init(name: "Reference", tla: "---- MODULE Reference ----\nX == \(value)\n====",
                                  cfg: "CHECK_DEADLOCK FALSE"))
        }
        func key(reference: TLAModuleBundle, limit: Int, cfgPin: String? = nil) throws -> String {
            try UpstreamTLCParity.cacheKey(id: "reference-case", rendered: rendered,
                reference: reference,
                expectedModuleSHA256: SHA256.hex(Data(reference.tla.utf8)),
                expectedCFGSHA256: cfgPin ?? SHA256.hex(Data(reference.cfg.utf8)),
                maximumStates: limit,
                decisive: false, pin: pin)
        }
        let baseline = try key(reference: reference(1), limit: 100)
        #expect(baseline == (try key(reference: reference(1), limit: 100)))
        #expect(baseline != (try key(reference: reference(2), limit: 100)))
        #expect(baseline != (try key(reference: reference(1), limit: 101)))
        #expect(throws: UpstreamTLCParityError.inputMismatch("reference-case")) {
            try key(reference: reference(1), limit: 100,
                cfgPin: SHA256.hex(Data("stale configuration".utf8)))
        }
    }
}
