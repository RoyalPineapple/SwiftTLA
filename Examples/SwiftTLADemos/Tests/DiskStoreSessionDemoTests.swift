import Testing
@testable import SwiftTLADemos

struct DiskStoreSessionDemoTests {
    @Test("disk operations run only after the generated store opens")
    func diskTransitions() throws {
        var machine = DiskStoreSession()

        try DiskStoreSession.verifySpec()
        try DiskStoreSession.verifyTransitions()
        try DiskStoreSession.verifyInvariants()

        _ = try machine.apply(.transition(process: .open))
        _ = try machine.apply(.transition(process: .write))

        #expect(machine.state.phase == .ready)
    }
}
