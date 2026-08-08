import SwiftTLA
import SwiftTLAMacros
import CoreBluetooth

@TLAActor
public actor Peripheral: NSObject, CBPeripheralDelegate {
    public static var spec: TLASpec {
        TLASpec("Peripheral") {
            let phase = Var<Int>("phase")
            let servicesDiscovered = Var<Bool>("servicesDiscovered")
            let charsDiscovered = Var<Bool>("charsDiscovered")
            Variable(phase, 0)
            Variable(servicesDiscovered, false)
            Variable(charsDiscovered, false)

            Action("beginConnect")       { phase == 0 && phase.becomes(1) }
            Action("finishConnect")      { phase == 1 && phase.becomes(2) }
            Action("finishFailConnect")  { phase == 1 && phase.becomes(0) }
            Action("disconnect")         { (phase == 2 || phase == 4 || phase == 6) && phase.becomes(7) }
            Action("finishDisconnect")   { phase == 7 && phase.becomes(0)
                                           && servicesDiscovered.becomes(false)
                                           && charsDiscovered.becomes(false) }
            Action("beginDiscover")     { phase == 2 && phase.becomes(3) }
            Action("finishDiscover")    { phase == 3 && phase.becomes(4)
                                           && servicesDiscovered.becomes(true) }
            Action("beginDiscoverChars") { phase == 4 && phase.becomes(5) }
            Action("finishDiscoverChars") { phase == 5 && phase.becomes(6)
                                             && charsDiscovered.becomes(true) }

            Invariant("resetOnDisconnect") { (phase != 0) || (!servicesDiscovered && !charsDiscovered) }
        }
    }

    public enum Phase: Int {
        case disconnected = 0, connecting, connected,
             discoveringServices, servicesDiscovered,
             discoveringChars, ready, disconnecting
    }
    public var currentPhase: Phase { Phase(rawValue: _state.phase)! }
    public var isReady: Bool { currentPhase == .ready }

    public let cbPeripheral: CBPeripheral

    public init(peripheral: CBPeripheral) {
        self.cbPeripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    public func didConnect() {
        guard currentPhase == .disconnected else { return }
        beginConnect()
    }

    public func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        guard currentPhase == .connected else { return }
        beginDiscover()
        cbPeripheral.discoverServices(serviceUUIDs)
    }

    public func readValue(for characteristic: CBCharacteristic) {
        guard currentPhase == .ready else { return }
        cbPeripheral.readValue(for: characteristic)
    }

    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        guard currentPhase == .ready else { return }
        cbPeripheral.writeValue(data, for: characteristic, type: type)
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { await self.finishDiscover() }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        Task { await self.finishDiscoverChars() }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {}
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {}
}
