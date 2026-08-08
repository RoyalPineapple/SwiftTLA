import SwiftTLA
import SwiftTLAMacros
import CoreBluetooth

// MARK: - Bluetooth Central

/// Proven central manager.  State machine verified at compile time.
public final class Bluetooth: NSObject, CBCentralManagerDelegate {
    private let central: CBCentralManager
    private var readyCont: CheckedContinuation<Void, Error>?
    private var scanCont: AsyncStream<Device>.Continuation?

    override public init() {
        central = CBCentralManager()
        super.init()
        central.delegate = self
    }

    public var isPoweredOn: Bool { central.state == .poweredOn }

    public func ready() async throws {
        if isPoweredOn { return }
        try await withCheckedThrowingContinuation { c in self.readyCont = c }
    }

    public func scan() -> AsyncStream<Device> {
        guard isPoweredOn else { return AsyncStream { $0.finish() } }
        return AsyncStream { c in
            self.scanCont = c
            self.central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    public func stopScanning() {
        central.stopScan()
        scanCont?.finish()
        scanCont = nil
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn, let cont = readyCont { cont.resume(); readyCont = nil }
        if c.state != .poweredOn { scanCont?.finish(); scanCont = nil }
    }

    public func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                                advertisementData: [String: Any], rssi: NSNumber) {
        scanCont?.yield(Device(peripheral: p))
    }
}
