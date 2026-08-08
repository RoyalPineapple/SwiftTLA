import SwiftTLA
import SwiftTLAMacros
import CoreBluetooth

private final class BleDelegate: NSObject, CBCentralManagerDelegate {
    weak var actor: Bluetooth?
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Task { await actor?.updateState(c.state) }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        Task { await actor?.didDiscover(Device(peripheral: p)) }
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {}
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: (any Error)?) {}
}

@TLAActor
public actor Bluetooth {
    public static var spec: TLASpec {
        TLASpec("Bluetooth") {
            let phase = Var<Int>("phase")
            Variable(phase, 0)
            Action("toPoweredOn")    { (phase == 0 || phase == 1 || phase == 4) && phase.becomes(5) }
            Action("toPoweredOff")   { (phase == 0 || phase == 1 || phase == 5) && phase.becomes(4) }
            Action("toUnsupported")  { phase == 0 && phase.becomes(2) }
            Action("toUnauthorized") { phase == 0 && phase.becomes(3) }
            Action("toResetting")    { (phase == 4 || phase == 5) && phase.becomes(1) }
            Action("startScan")      { phase == 5 && phase.becomes(6) }
            Action("stopScan")       { phase == 6 && phase.becomes(5) }
            Invariant("validPhase") { phase >= 0 && phase <= 6 }
        }
    }

    public var centralState: CBManagerState {
        switch _state.phase {
        case 0:  return .unknown
        case 1:  return .resetting
        case 2:  return .unsupported
        case 3:  return .unauthorized
        case 4:  return .poweredOff
        case 5:  return .poweredOn
        case 6:  return .poweredOn  // scanning = poweredOn for the framework
        default: return .unknown
        }
    }
    public var isReady: Bool { _state.phase == 5 }

    private let delegate = BleDelegate()
    private let central: CBCentralManager
    private var readyCont: CheckedContinuation<Void, Error>?
    private var scanStream: AsyncStream<Device>?
    private var scanCont: AsyncStream<Device>.Continuation?

    public init() {
        central = CBCentralManager()
        delegate.actor = self
        central.delegate = delegate
    }

    public func ready() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in self.readyCont = c }
    }

    public func scan() -> AsyncStream<Device> {
        let (stream, cont) = AsyncStream<Device>.makeStream()
        scanStream = stream
        scanCont = cont
        startScan()
        central.scanForPeripherals(withServices: nil, options: nil)
        return stream
    }

    public func stopScanning() {
        stopScan()
        central.stopScan()
        scanCont?.finish()
        scanCont = nil
    }

    public func connect(_ device: Device) async throws {
        guard isReady else { throw BleError.notReady }
        central.connect(device.peripheral, options: nil)
        try await device.waitForConnection()
    }

    func updateState(_ s: CBManagerState) {
        switch s {
        case .poweredOn:  toPoweredOn()
        case .poweredOff: toPoweredOff()
        case .unsupported: toUnsupported()
        case .unauthorized: toUnauthorized()
        case .resetting:  toResetting()
        default: break
        }
        if s == .poweredOn, let c = readyCont { c.resume(); readyCont = nil }
        if s != .poweredOn { scanCont?.finish(); scanCont = nil }
    }

    func didDiscover(_ device: Device) { scanCont?.yield(device) }
}

public enum BleError: Error { case notReady }
