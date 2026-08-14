import Testing
@testable import SwiftTLADemos

struct PeripheralSessionDemoTests {
    @Test("peripheral session keeps discovery state in a typed generated record")
    func generatedSessionTransitions() throws {
        var machine = PeripheralSession()

        try PeripheralSession.verifySpec()
        try PeripheralSession.verifyTransitions()
        try PeripheralSession.verifyInvariants()

        _ = try machine.apply(.transition(process: .connected))
        _ = try machine.apply(.transition(process: .beginDiscovery))
        _ = try machine.apply(.transition(process: .finishDiscovery))
        #expect(machine.state.session[PeripheralSession.SessionSchema.phase] == .ready)
        #expect(machine.state.session[PeripheralSession.SessionSchema.servicesDiscovered])
    }
}
