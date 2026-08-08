import Foundation
import CoreBluetooth

private final class DeviceDelegate: NSObject, CBPeripheralDelegate {
    weak var actor: Device?
    func peripheral(_ p: CBPeripheral, didDiscoverServices e: (any Error)?) {
        if let e { actor?.servicesCont?.resume(throwing: e) }
        else { actor?.servicesCont?.resume(returning: p.services ?? []) }
        actor?.servicesCont = nil
    }
}

@TLAActor
public actor Device {
    public static var spec: TLASpec {
        TLASpec("Device") {
            let phase = Var<Int>("phase")
            let servicesDiscovered = Var<Bool>("servicesDiscovered")
            Variable(phase, 0)
            Variable(servicesDiscovered, false)

            Action("didConnect")       { phase == 0 && phase.becomes(1) }
            Action("beginDiscover")    { phase == 1 && phase.becomes(2) }
            Action("finishDiscover")   { phase == 2 && phase.becomes(3) && servicesDiscovered.becomes(true) }
            Action("disconnect")       { phase == 3 && phase.becomes(0) && servicesDiscovered.becomes(false) }

            Invariant("validPhase")          { phase >= 0 && phase <= 3 }
            Invariant("readyImpliesDiscovered") { (phase != 3) || servicesDiscovered }
        }
    }

    public let peripheral: CBPeripheral
    public var name: String? { peripheral.name }

    private let delegate = DeviceDelegate()
    fileprivate var connectCont: CheckedContinuation<Void, Error>?
    fileprivate var servicesCont: CheckedContinuation<[CBService], Error>?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        delegate.actor = self
        peripheral.delegate = delegate
    }

    public func waitForConnection() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            self.connectCont = c
        }
    }

    func didConnect() { didConnect(); connectCont?.resume(); connectCont = nil }
    func didFail(_ e: Error?) { connectCont?.resume(throwing: e ?? BleError.notReady); connectCont = nil }

    public func discoverServices(_ uuids: [CBUUID]? = nil) async throws -> [CBService] {
        guard _state.phase == 1 else { throw BleError.notReady }
        beginDiscover()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[CBService], Error>) in
            self.servicesCont = c
            self.peripheral.discoverServices(uuids)
        }
    }
}
