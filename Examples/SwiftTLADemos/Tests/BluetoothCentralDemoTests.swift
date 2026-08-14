import Testing
@testable import SwiftTLADemos

struct BluetoothCentralDemoTests {
    @Test("Bluetooth central exposes generated typed transitions")
    func generatedCentralTransitions() throws {
        var machine = BluetoothCentral()

        try BluetoothCentral.verifySpec()
        try BluetoothCentral.verifyTransitions()
        try BluetoothCentral.verifyInvariants()

        _ = try machine.apply(.transition(process: .poweredOn))
        #expect(machine.state.phase == .poweredOn)
        _ = try machine.apply(.transition(process: .startScan))
        #expect(machine.state.phase == .scanning)
        _ = try machine.apply(.transition(process: .stopScan))
        #expect(machine.state.phase == .poweredOn)
    }
}
