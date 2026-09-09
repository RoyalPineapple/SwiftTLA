import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// A deliberately malformed formal fixture exercises the generated boundary.
@TLAModel
private struct ShrinkingCollectionDomain {
    struct Device: Identifiable, Sendable { let id: Int }
    static var spec: TLASpec {
        TLASpec("ShrinkingCollectionDomain") {
            let devices = CollectionVar<Device, Int>("devices")
            ModelCollection(devices, verificationScope: 1, initial: 0)
            SwiftTLA.Action("shrink") {
                ActionExpr.assign(.named("devices"), StateExpr.functionLiteral(
                    StateExpr.setFilter(StateExpr.variable("devices").domain, "member", false),
                    "member",
                    0
                ))
            }
        }
    }
}

@Suite struct NativeCollectionDomainTests {
    @Test("native collection domain changes fail before committing state")
    func domainShrinkIsTransactional() throws {
        var machine = try ShrinkingCollectionDomain.makeMachine(devices: [7])
        let before = machine.state
        #expect(before.devices == [7: 0])
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try machine.send(.shrink)
        }
        #expect(machine.state == before)
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try machine.send(.shrink)
        }
        #expect(machine.state == before)
    }
}
