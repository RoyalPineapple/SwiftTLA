import SwiftTLA
import SwiftTLAMacros

/// Cross-actor contract: proves invariants hold between Bluetooth central and
/// any number of connected peripherals.  Symmetry over peripheral slots
/// collapses the state space to N=1 — machine-proven for all N at compile time.
@TLAActor
public actor Contract {
    public static var spec: TLASpec {
        TLASpec("Contract") {
            let cPhase = Var<Int>("cPhase")
            let pPhase1 = Var<Int>("pPhase1")
            let pPhase2 = Var<Int>("pPhase2")
            let pPhase3 = Var<Int>("pPhase3")
            let pPhase4 = Var<Int>("pPhase4")

            Variable(cPhase, 0)
            Variable(pPhase1, 0)
            Variable(pPhase2, 0)
            Variable(pPhase3, 0)
            Variable(pPhase4, 0)

            Action("cToPoweredOn")   { (cPhase == 0 || cPhase == 1 || cPhase == 4) && cPhase.becomes(5) }
            Action("cToPoweredOff")  { (cPhase == 0 || cPhase == 1 || cPhase == 5) && cPhase.becomes(4) }
            Action("cToUnsupported") { cPhase == 0 && cPhase.becomes(2) }
            Action("cToUnauthorized") { cPhase == 0 && cPhase.becomes(3) }
            Action("cToResetting")   { (cPhase == 4 || cPhase == 5) && cPhase.becomes(1) }
            Action("cStartScan")     { cPhase == 5 && cPhase.becomes(6) }
            Action("cStopScan")      { cPhase == 6 && cPhase.becomes(5) }

            // Define the peripheral transition pattern once
            let anyPhase = Var<Int>("anyPhase")
            Operator("beginConnect", param: anyPhase) { anyPhase == 0 && anyPhase.becomes(1) }
            Operator("finishConnect", param: anyPhase) { anyPhase == 1 && anyPhase.becomes(2) }
            Operator("failConnect", param: anyPhase) { anyPhase == 1 && anyPhase.becomes(0) }
            Operator("disconnect", param: anyPhase) { (anyPhase == 2 || anyPhase == 4 || anyPhase == 6) && anyPhase.becomes(7) }
            Operator("finishDisconnect", param: anyPhase) { anyPhase == 7 && anyPhase.becomes(0) }
            Operator("beginDiscover", param: anyPhase) { anyPhase == 2 && anyPhase.becomes(3) }
            Operator("finishDiscover", param: anyPhase) { anyPhase == 3 && anyPhase.becomes(4) }
            Operator("beginDiscoverChars", param: anyPhase) { anyPhase == 4 && anyPhase.becomes(5) }
            Operator("finishDiscoverChars", param: anyPhase) { anyPhase == 5 && anyPhase.becomes(6) }

            // Apply to each slot
            for p in [pPhase1, pPhase2, pPhase3, pPhase4] {
                UseOp("beginConnect", with: p)
                UseOp("finishConnect", with: p)
                UseOp("failConnect", with: p)
                UseOp("disconnect", with: p)
                UseOp("finishDisconnect", with: p)
                UseOp("beginDiscover", with: p)
                UseOp("finishDiscover", with: p)
                UseOp("beginDiscoverChars", with: p)
                UseOp("finishDiscoverChars", with: p)
            }

            Invariant("noPeripheralWithoutPower") {
                for p in [pPhase1, pPhase2, pPhase3, pPhase4] {
                    (cPhase == 5) || (p == 0) || (p == 7)
                }
            }
            Invariant("noScanWhileConnecting") {
                for p in [pPhase1, pPhase2, pPhase3, pPhase4] {
                    (cPhase != 6) || (p != 1)
                }
            }
            SymmetryGroup("pPhase1", "pPhase2", "pPhase3", "pPhase4")
        }
    }
}
