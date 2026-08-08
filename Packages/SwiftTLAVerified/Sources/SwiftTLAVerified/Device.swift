import Foundation
import CoreBluetooth

// MARK: - Device (Peripheral)

/// A discovered BLE peripheral.  Device state machine is verified in CrossActor.
public final class Device: NSObject, CBPeripheralDelegate {
    public let peripheral: CBPeripheral
    public var name: String? { peripheral.name }
    public var rssi: NSNumber? { nil }  // populated by Bluetooth delegate

    private var connectCont: CheckedContinuation<Void, Error>?
    private var servicesCont: CheckedContinuation<[Service], Error>?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    /// Connect and discover all services.
    public func connect() async throws -> [Service] {
        guard peripheral.state == .disconnected else { return [] }
        return try await withCheckedThrowingContinuation { c in
            self.connectCont = c
            // Connection initiated by central — we just wait for delegate
        }
    }

    /// Discover services.
    public func discoverServices(_ uuids: [CBUUID]? = nil) async throws -> [Service] {
        guard peripheral.state == .connected else { throw DeviceError.notConnected }
        return try await withCheckedThrowingContinuation { c in
            self.servicesCont = c
            peripheral.discoverServices(uuids)
        }
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error { servicesCont?.resume(throwing: error) }
        else {
            let services = (p.services ?? []).map { Service(service: $0) }
            servicesCont?.resume(returning: services)
        }
        servicesCont = nil
    }
}

// MARK: - Service

public final class Service {
    public let service: CBService
    public var uuid: CBUUID { service.uuid }

    init(service: CBService) { self.service = service }
}

// MARK: - Errors

public enum DeviceError: Error {
    case notConnected
}
