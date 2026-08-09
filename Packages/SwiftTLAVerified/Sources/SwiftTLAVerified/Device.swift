import Foundation
import CoreBluetooth
import SwiftTLA
import SwiftTLAMacros

private final class DeviceDelegate: NSObject, CBPeripheralDelegate {
    weak var actor: Device?
    func peripheral(_ p: CBPeripheral, didDiscoverServices e: (any Error)?) {
        Task { await actor?.handleDiscoverServices(e) }
    }
}

@TLAActor
public actor Device: Identifiable {
    public static var spec: TLASpec {
        TLASpec("Device") {
            let phase = StateVar(0)
            let servicesDiscovered = StateVar(false)

            // 0=disconnected 1=connected 2=discovering 3=ready
            Action("didConnect")       { phase == 0 && phase.becomes(1) }
            Action("beginDiscover")    { phase == 1 && phase.becomes(2) }
            Action("finishDiscover")   { phase == 2 && phase.becomes(3) && servicesDiscovered.becomes(true) }
            Action("disconnect")       { phase == 3 && phase.becomes(0) && servicesDiscovered.becomes(false) }

            Invariant("validPhase")              { phase >= 0 && phase <= 3 }
            Invariant("readyImpliesDiscovered")  { (phase != 3) || servicesDiscovered }
        }
    }

    public nonisolated let id: UUID
    private let backingPeripheral: CBPeripheral?
    public var peripheral: CBPeripheral {
        guard let backingPeripheral else {
            preconditionFailure("Identity-only devices do not have a Bluetooth peripheral")
        }
        return backingPeripheral
    }
    public var name: String? { backingPeripheral?.name }

    private let delegate = DeviceDelegate()
    private var connectCont: CheckedContinuation<Void, Error>?
    private var servicesCont: CheckedContinuation<[CBService], Error>?

    init(peripheral: CBPeripheral) {
        self.id = peripheral.identifier
        self.backingPeripheral = peripheral
        delegate.actor = self
        peripheral.delegate = delegate
    }

    init(id: UUID) {
        self.id = id
        self.backingPeripheral = nil
    }

    /// Called by Bluetooth central when connection succeeds
    func didConnect() { _didConnect(); connectCont?.resume(); connectCont = nil }
    func didFail(_ e: Error?) { connectCont?.resume(throwing: e ?? BleError.notReady); connectCont = nil }

    public func waitForConnection() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in self.connectCont = c }
    }

    public func discoverServices(_ uuids: [CBUUID]? = nil) async throws -> [CBService] {
        guard _state.phase == 1, let peripheral = backingPeripheral else { throw BleError.notReady }
        _beginDiscover()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[CBService], Error>) in
            self.servicesCont = c
            peripheral.discoverServices(uuids)
        }
    }

    func handleDiscoverServices(_ e: (any Error)?) {
        _finishDiscover()
        if let e { servicesCont?.resume(throwing: e) }
        else { servicesCont?.resume(returning: backingPeripheral?.services ?? []) }
        servicesCont = nil
    }
}
