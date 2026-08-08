import Foundation
import CoreBluetooth

public final class Device: NSObject, CBPeripheralDelegate {
    public let peripheral: CBPeripheral
    public var name: String? { peripheral.name }

    private var connectCont: CheckedContinuation<Void, Error>?
    private var servicesCont: CheckedContinuation<[CBService], Error>?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    func waitForConnection() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            self.connectCont = c
        }
    }

    func didConnect() { connectCont?.resume(); connectCont = nil }
    func didFail(_ error: Error?) { connectCont?.resume(throwing: error ?? BleError.notReady); connectCont = nil }

    public func discoverServices(_ uuids: [CBUUID]? = nil) async throws -> [CBService] {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<[CBService], Error>) in
            self.servicesCont = c
            peripheral.discoverServices(uuids)
        }
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error { servicesCont?.resume(throwing: error) }
        else { servicesCont?.resume(returning: p.services ?? []) }
        servicesCont = nil
    }
}
