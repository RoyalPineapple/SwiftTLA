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

            // Peripheral slots 1-4, unrolled (parser can't yet resolve loop vars in action bodies)
            // Slot 1
            Action("p1_beginConnect")         { pPhase1 == 0 && pPhase1.becomes(1) }
            Action("p1_finishConnect")        { pPhase1 == 1 && pPhase1.becomes(2) }
            Action("p1_failConnect")          { pPhase1 == 1 && pPhase1.becomes(0) }
            Action("p1_disconnect")           { (pPhase1 == 2 || pPhase1 == 4 || pPhase1 == 6) && pPhase1.becomes(7) }
            Action("p1_finishDisconnect")     { pPhase1 == 7 && pPhase1.becomes(0) }
            Action("p1_beginDiscover")        { pPhase1 == 2 && pPhase1.becomes(3) }
            Action("p1_finishDiscover")       { pPhase1 == 3 && pPhase1.becomes(4) }
            Action("p1_beginDiscoverChars")   { pPhase1 == 4 && pPhase1.becomes(5) }
            Action("p1_finishDiscoverChars")  { pPhase1 == 5 && pPhase1.becomes(6) }
            // Slot 2
            Action("p2_beginConnect")         { pPhase2 == 0 && pPhase2.becomes(1) }
            Action("p2_finishConnect")        { pPhase2 == 1 && pPhase2.becomes(2) }
            Action("p2_failConnect")          { pPhase2 == 1 && pPhase2.becomes(0) }
            Action("p2_disconnect")           { (pPhase2 == 2 || pPhase2 == 4 || pPhase2 == 6) && pPhase2.becomes(7) }
            Action("p2_finishDisconnect")     { pPhase2 == 7 && pPhase2.becomes(0) }
            Action("p2_beginDiscover")        { pPhase2 == 2 && pPhase2.becomes(3) }
            Action("p2_finishDiscover")       { pPhase2 == 3 && pPhase2.becomes(4) }
            Action("p2_beginDiscoverChars")   { pPhase2 == 4 && pPhase2.becomes(5) }
            Action("p2_finishDiscoverChars")  { pPhase2 == 5 && pPhase2.becomes(6) }
            // Slot 3
            Action("p3_beginConnect")         { pPhase3 == 0 && pPhase3.becomes(1) }
            Action("p3_finishConnect")        { pPhase3 == 1 && pPhase3.becomes(2) }
            Action("p3_failConnect")          { pPhase3 == 1 && pPhase3.becomes(0) }
            Action("p3_disconnect")           { (pPhase3 == 2 || pPhase3 == 4 || pPhase3 == 6) && pPhase3.becomes(7) }
            Action("p3_finishDisconnect")     { pPhase3 == 7 && pPhase3.becomes(0) }
            Action("p3_beginDiscover")        { pPhase3 == 2 && pPhase3.becomes(3) }
            Action("p3_finishDiscover")       { pPhase3 == 3 && pPhase3.becomes(4) }
            Action("p3_beginDiscoverChars")   { pPhase3 == 4 && pPhase3.becomes(5) }
            Action("p3_finishDiscoverChars")  { pPhase3 == 5 && pPhase3.becomes(6) }
            // Slot 4
            Action("p4_beginConnect")         { pPhase4 == 0 && pPhase4.becomes(1) }
            Action("p4_finishConnect")        { pPhase4 == 1 && pPhase4.becomes(2) }
            Action("p4_failConnect")          { pPhase4 == 1 && pPhase4.becomes(0) }
            Action("p4_disconnect")           { (pPhase4 == 2 || pPhase4 == 4 || pPhase4 == 6) && pPhase4.becomes(7) }
            Action("p4_finishDisconnect")     { pPhase4 == 7 && pPhase4.becomes(0) }
            Action("p4_beginDiscover")        { pPhase4 == 2 && pPhase4.becomes(3) }
            Action("p4_finishDiscover")       { pPhase4 == 3 && pPhase4.becomes(4) }
            Action("p4_beginDiscoverChars")   { pPhase4 == 4 && pPhase4.becomes(5) }
            Action("p4_finishDiscoverChars")  { pPhase4 == 5 && pPhase4.becomes(6) }

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
