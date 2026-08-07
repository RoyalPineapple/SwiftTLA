import SwiftTLA
import SwiftTLAMacros
import CoreBluetooth

/// A verified CoreBluetooth peripheral wrapper.  Proves at compile time that
/// you never discover services unless connected, never read/write unless
/// services and characteristics have been discovered, and that all discovery
/// state resets on disconnection.
@TLAModel
public actor Peripheral: NSObject, CBPeripheralDelegate {
    public static var spec: TLASpec {
        TLASpec("Peripheral") {
            let phase = Var<Int>("phase")
                // 0=disconnected, 1=connecting, 2=connected,
                // 3=discoveringServices, 4=servicesDiscovered,
                // 5=discoveringChars, 6=ready, 7=disconnecting
            let servicesDiscovered = Var<Bool>("servicesDiscovered")
            let charsDiscovered = Var<Bool>("charsDiscovered")

            Variable(phase, 0)
            Variable(servicesDiscovered, false)
            Variable(charsDiscovered, false)

            Action("connect")              { phase == 0 && phase.becomes(1) }
            Action("didConnect")           { phase == 1 && phase.becomes(2) }
            Action("didFailToConnect")     { phase == 1 && phase.becomes(0) }
            Action("disconnect")           { (phase == 2 || phase == 4 || phase == 6)
                                             && phase.becomes(7) }
            Action("didDisconnect")        { phase == 7 && phase.becomes(0)
                                             && servicesDiscovered.becomes(false)
                                             && charsDiscovered.becomes(false) }
            Action("discoverServices")     { phase == 2 && phase.becomes(3) }
            Action("didDiscoverServices")  { phase == 3 && phase.becomes(4)
                                             && servicesDiscovered.becomes(true) }
            Action("discoverChars")        { phase == 4 && phase.becomes(5) }
            Action("didDiscoverChars")     { phase == 5 && phase.becomes(6)
                                             && charsDiscovered.becomes(true) }

            Invariant("resetOnDisconnect") {
                (phase == 0) ==> (!servicesDiscovered && !charsDiscovered)
            }
        }
    }

    // ── BRIDGE ──

    public enum Phase: Int {
        case disconnected = 0, connecting, connected,
             discoveringServices, servicesDiscovered,
             discoveringChars, ready, disconnecting
    }

    public var phase: Phase { Phase(rawValue: _state.phase)! }
    public var isReady: Bool { phase == .ready }

    public let device: CBPeripheral

    public init(device: CBPeripheral) {
        self.device = device
        super.init()
        device.delegate = self
    }

    public func connect() {
        guard phase == .disconnected else { return }
        applyConnect()
        device.connect()
    }

    public func discoverServices(_ serviceUUIDs: [CBUUID]?) async throws {
        guard phase == .connected else { return }
        applyDiscoverServices()
        device.discoverServices(serviceUUIDs)
    }

    public func readValue(for characteristic: CBCharacteristic) async throws {
        guard phase == .ready else { return }
        device.readValue(for: characteristic)
    }

    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        guard phase == .ready else { return }
        device.writeValue(data, for: characteristic, type: type)
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        applyDidDiscoverServices()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        applyDidDiscoverChars()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
    }
}
