import SwiftTLA
import SwiftTLAMacros

@TLAActor
public actor DynamicCrossActor {
    public static var spec: TLASpec {
        TLASpec("DynamicCrossActor") {
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

            // Central: 0=unknown 1=resetting 2=unsupported 3=unauthorized 4=poweredOff 5=poweredOn 6=scanning
            Action("cToPoweredOn")   { (cPhase == 0 || cPhase == 1 ||
                                        cPhase == 4) && cPhase.becomes(5) }
            Action("cToPoweredOff")  { (cPhase == 0 || cPhase == 1 ||
                                        cPhase == 5) && cPhase.becomes(4) }
            Action("cToUnsupported") { cPhase == 0 && cPhase.becomes(2) }
            Action("cToUnauthorized") { cPhase == 0 && cPhase.becomes(3) }
            Action("cToResetting")   { (cPhase == 4 || cPhase == 5) && cPhase.becomes(1) }
            Action("cStartScan")     { cPhase == 5 && cPhase.becomes(6) }
            Action("cStopScan")      { cPhase == 6 && cPhase.becomes(5) }

            // Peripheral slots 1-4: 0=disconnected 1=connecting 2=connected
            // 3=discoveringServices 4=servicesDiscovered 5=discoveringChars 6=ready 7=disconnecting
            for p in [pPhase1, pPhase2, pPhase3, pPhase4] {
                Action("beginConnect\(p)")         { p == 0 && p.becomes(1) }
                Action("finishConnect\(p)")        { p == 1 && p.becomes(2) }
                Action("failConnect\(p)")          { p == 1 && p.becomes(0) }
                Action("disconnect\(p)")           { (p == 2 || p == 4 || p == 6) && p.becomes(7) }
                Action("finishDisconnect\(p)")     { p == 7 && p.becomes(0) }
                Action("beginDiscover\(p)")        { p == 2 && p.becomes(3) }
                Action("finishDiscover\(p)")       { p == 3 && p.becomes(4) }
                Action("beginDiscoverChars\(p)")   { p == 4 && p.becomes(5) }
                Action("finishDiscoverChars\(p)")  { p == 5 && p.becomes(6) }
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

            // Symmetry: all peripheral slots are interchangeable.
            // With a function-based model (slot → phase), symmetry over slots
            // collapses the state space to N=1 for verification.  TLC supports
            // this; @TLAModel parity is a future feature.
        }
    }
}
