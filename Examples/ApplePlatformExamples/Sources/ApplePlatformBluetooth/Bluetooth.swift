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
            /// The central's callback-visible lifecycle. Scanning is a state,
            /// not an implementation flag, so the model can rule out scans
            /// while the manager is unavailable.
            let phase = Var("phase", 0)
            Variable(phase)

            /// These actions model the state changes reported by
            /// `CBCentralManagerDelegate` plus the app's scan commands.
            Action("toPoweredOn")    { (phase == 0 || phase == 1 || phase == 4) && phase.becomes(5) }
            Action("toPoweredOff")   { (phase == 0 || phase == 1 || phase == 5) && phase.becomes(4) }
            Action("toUnsupported")  { phase == 0 && phase.becomes(2) }
            Action("toUnauthorized") { phase == 0 && phase.becomes(3) }
            Action("toResetting")    { (phase == 4 || phase == 5) && phase.becomes(1) }
            Action("startScan")      { phase == 5 && phase.becomes(6) }
            Action("stopScan")       { phase == 6 && phase.becomes(5) }
            /// Delegate callbacks must always leave the central in one of the
            /// seven known CoreBluetooth lifecycle states.
            Invariant("validPhase") { phase >= 0 && phase <= 6 }
        }
    }

    public var isReady: Bool { _state.phase == 5 }

    private let delegate = BleDelegate()
    private var central: CBCentralManager!
    private var readyCont: CheckedContinuation<Void, Error>?
    private var scanCont: AsyncStream<Device>.Continuation?

    public init() {
        central = CBCentralManager()
        central.delegate = delegate
        delegate.actor = self
    }

    public func ready() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in self.readyCont = c }
    }

    public func scan() -> AsyncStream<Device> {
        let (stream, cont) = AsyncStream<Device>.makeStream()
        scanCont = cont
        startScan()
        central.scanForPeripherals(withServices: nil, options: nil)
        return stream
    }

    public func stopScanning() {
        stopScan(); central.stopScan(); scanCont?.finish(); scanCont = nil
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
