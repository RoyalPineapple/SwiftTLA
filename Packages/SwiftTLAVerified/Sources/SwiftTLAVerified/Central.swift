import SwiftTLA
import SwiftTLAMacros
import CoreBluetooth

@TLAActor
public actor Central: NSObject, CBCentralManagerDelegate {
    public static var spec: TLASpec {
        TLASpec("Central") {
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
            // All other invariants are structural — guards on actions prevent
            // transitions from invalid states.  Cross-actor invariants
            // (e.g. no Peripheral connected while Central poweredOff) are
            // verified by TLC composition.
        }
    }

    public enum Phase: Int {
        case unknown = 0, resetting, unsupported, unauthorized, poweredOff, poweredOn, scanning
    }
    public var currentPhase: Phase { Phase(rawValue: _state.phase)! }
    public var isReady: Bool { currentPhase == .poweredOn }

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
        try await ready()
        toPoweredOn()
        startScan()
        central.scanForPeripherals(withServices: services, options: nil)
    }

    public func stop() {
        stopScan()
        central.stopScan()
    }

    public func connect(_ peripheral: CBPeripheral) async throws {
        try await ready()
        central.connect(peripheral, options: nil)
    }

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = central.state
        Task { await self.updateState(newState) }
    }

    private func updateState(_ cbState: CBManagerState) {
        switch cbState {
        case .poweredOn:  toPoweredOn()
        case .poweredOff: toPoweredOff()
        case .unsupported: toUnsupported()
        case .unauthorized: toUnauthorized()
        case .resetting:  toResetting()
        case .unknown:    break
        @unknown default: break
        }
        if cbState == .poweredOn, let c = readyContinuation {
            c.resume()
            readyContinuation = nil
        }
    }
}
