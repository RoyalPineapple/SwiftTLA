import SwiftTLA
import SwiftTLAMacros
import CoreBluetooth

@TLAActor
public actor CrossActor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    public static var spec: TLASpec {
        TLASpec("CrossActor") {
            // Central: 0=unknown 1=resetting 2=unsupported 3=unauthorized 4=poweredOff 5=poweredOn 6=scanning
            let cPhase = Var<Int>("cPhase")
            let pPhase1 = Var<Int>("pPhase1")
            let pPhase2 = Var<Int>("pPhase2")
            let pPhase3 = Var<Int>("pPhase3")

            Variable(cPhase, 0)
            Variable(pPhase1, 0)
            Variable(pPhase2, 0)
            Variable(pPhase3, 0)

            Action("cToPoweredOn")   { (cPhase == 0 || cPhase == 1 ||
                                        cPhase == 4) && cPhase.becomes(5) }
            Action("cToPoweredOff")  { (cPhase == 0 || cPhase == 1 ||
                                        cPhase == 5) && cPhase.becomes(4) }
            Action("cToUnsupported") { cPhase == 0 && cPhase.becomes(2) }
            Action("cToUnauthorized") { cPhase == 0 && cPhase.becomes(3) }
            Action("cToResetting")   { (cPhase == 4 || cPhase == 5) && cPhase.becomes(1) }
            Action("cStartScan")     { cPhase == 5 && cPhase.becomes(6) }
            Action("cStopScan")      { cPhase == 6 && cPhase.becomes(5) }

            // Peripheral slots 1-3: 0=disconnected 1=connecting 2=connected
            // 3=discoveringServices 4=servicesDiscovered 5=discoveringChars 6=ready 7=disconnecting
            for p in [pPhase1, pPhase2, pPhase3] {
                Action("beginConnect\(p)")        { p == 0 && p.becomes(1) }
                Action("finishConnect\(p)")       { p == 1 && p.becomes(2) }
                Action("failConnect\(p)")         { p == 1 && p.becomes(0) }
                Action("disconnect\(p)")          { (p == 2 || p == 4 || p == 6) && p.becomes(7) }
                Action("finishDisconnect\(p)")    { p == 7 && p.becomes(0) }
                Action("beginDiscover\(p)")       { p == 2 && p.becomes(3) }
                Action("finishDiscover\(p)")      { p == 3 && p.becomes(4) }
                Action("beginDiscoverChars\(p)")  { p == 4 && p.becomes(5) }
                Action("finishDiscoverChars\(p)") { p == 5 && p.becomes(6) }
            }

            Invariant("noPeripheralWithoutPower") {
                for p in [pPhase1, pPhase2, pPhase3] {
                    (cPhase == 5) || (p == 0) || (p == 7)
                }
            }
            Invariant("noScanWhileConnecting") {
                for p in [pPhase1, pPhase2, pPhase3] {
                    (cPhase != 6) || (p != 1)
                }
            }
        }
    }

    // ── DELEGATE WIRING ──
    private var central: CBCentralManager!
    private var slots: [Int: CBPeripheral] = [:]
    private var readyCont: CheckedContinuation<Void, Error>?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public func ready() async throws {
        if _state.cPhase == 5 { return }
        try await withCheckedThrowingContinuation { c in self.readyCont = c }
    }
    public func scan() async throws {
        try await ready(); cStartScan()
        central.scanForPeripherals(withServices: nil, options: nil)
    }
    public func stop() { cStopScan(); central.stopScan() }

    private func slot(_ p: CBPeripheral) -> Int? { slots.first(where: { $1 === p })?.key }
    private func dispatch(_ slot: Int, _ fn: (Int) -> Void) { fn(slot) }
}

extension CrossActor {
    nonisolated public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Task { await self.updateState(c.state) }
    }
    private func updateState(_ s: CBManagerState) {
        switch s {
        case .poweredOn: cToPoweredOn()
        case .poweredOff: cToPoweredOff()
        case .unsupported: cToUnsupported()
        case .unauthorized: cToUnauthorized()
        case .resetting: cToResetting()
        default: break
        }
        if s == .poweredOn, let c = readyCont { c.resume(); readyCont = nil }
    }
}
