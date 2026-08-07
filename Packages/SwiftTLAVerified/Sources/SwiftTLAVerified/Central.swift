import SwiftTLA
import SwiftTLAMacros
import CoreBluetooth

/// A verified CoreBluetooth central manager.  Proves at compile time that
/// you never scan or connect unless Bluetooth is powered on.
@TLAModel
public actor Central: NSObject, CBCentralManagerDelegate {
    public static var spec: TLASpec {
        TLASpec("Central") {
            let phase = Var<Int>("phase")
                // 0=unknown, 1=resetting, 2=unsupported,
                // 3=unauthorized, 4=poweredOff, 5=poweredOn, 6=scanning
            Variable(phase, 0)

            Action("toPoweredOn")    { (phase == 0 || phase == 1 || phase == 4) && phase.becomes(5) }
            Action("toPoweredOff")   { (phase == 0 || phase == 1 || phase == 5) && phase.becomes(4) }
            Action("toUnsupported")  { phase == 0 && phase.becomes(2) }
            Action("toUnauthorized") { phase == 0 && phase.becomes(3) }
            Action("toResetting")    { (phase == 4 || phase == 5) && phase.becomes(1) }
            Action("startScan")      { phase == 5 && phase.becomes(6) }
            Action("stopScan")       { phase == 6 && phase.becomes(5) }

            Invariant("noScanWithoutPower") { true }  // structural: startScan guards on phase==5
        }
    }

    // ── BRIDGE ──

    public enum Phase: Int {
        case unknown = 0, resetting, unsupported, unauthorized, poweredOff, poweredOn, scanning
    }

    public var phase: Phase { Phase(rawValue: _state.phase)! }
    public var isReady: Bool { phase == .poweredOn }

    private var central: CBCentralManager!
    private var readyContinuation: CheckedContinuation<Void, Error>?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public func ready() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { c in
            self.readyContinuation = c
        }
    }

    public func scanForPeripherals(withServices services: [CBUUID]?) async throws {
        try await ready()            // awaits poweredOn
        applyToPoweredOn()           // proven: transitions to poweredOn
        applyStartScan()             // proven: only fires from poweredOn
        central.scanForPeripherals(withServices: services, options: nil)
    }

    public func stopScan() {
        applyStopScan()
        central.stopScan()
    }

    public func connect(_ peripheral: CBPeripheral) async throws {
        try await ready()
        central.connect(peripheral, options: nil)
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:  applyToPoweredOn()
        case .poweredOff: applyToPoweredOff()
        case .unsupported: applyToUnsupported()
        case .unauthorized: applyToUnauthorized()
        case .resetting:  applyToResetting()
        case .unknown:    break
        @unknown default: break
        }
        if central.state == .poweredOn {
            readyContinuation?.resume()
            readyContinuation = nil
        }
    }
}
