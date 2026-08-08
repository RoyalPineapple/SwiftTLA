import SwiftTLA
import SwiftTLAMacros

/// Dynamic device manager.  Proves cross-actor invariants hold for up to N=3
/// concurrently active peripherals, with slot allocation/deallocation modeled
/// as a state machine.
@TLAActor
public actor DynamicCrossActor {
    public static var spec: TLASpec {
        TLASpec("DynamicCrossActor") {
            let cPhase = Var<Int>("cPhase")
            let pPhase1 = Var<Int>("pPhase1")
            let pPhase2 = Var<Int>("pPhase2")
            let pPhase3 = Var<Int>("pPhase3")

            Variable(cPhase, 0)
            Variable(pPhase1, 0)
            Variable(pPhase2, 0)
            Variable(pPhase3, 0)

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

            // Slot 1: 0=disconnected 1=connecting 2=connected 3=discoveringServices
            // 4=servicesDiscovered 5=discoveringChars 6=ready 7=disconnecting
            Action("p1_beginConnect")         { pPhase1 == 0 && pPhase1.becomes(1) }
            Action("p1_finishConnect")        { pPhase1 == 1 && pPhase1.becomes(2) }
            Action("p1_failConnect")          { pPhase1 == 1 && pPhase1.becomes(0) }
            Action("p1_disconnect")           { (pPhase1 == 2 || pPhase1 == 4 || pPhase1 == 6) && pPhase1.becomes(7) }
            Action("p1_finishDisconnect")     { pPhase1 == 7 && pPhase1.becomes(0) }
            Action("p1_beginDiscover")        { pPhase1 == 2 && pPhase1.becomes(3) }
            Action("p1_finishDiscover")       { pPhase1 == 3 && pPhase1.becomes(4) }
            Action("p1_beginDiscoverChars")   { pPhase1 == 4 && pPhase1.becomes(5) }
            Action("p1_finishDiscoverChars")  { pPhase1 == 5 && pPhase1.becomes(6) }

            Action("p2_beginConnect")         { pPhase2 == 0 && pPhase2.becomes(1) }
            Action("p2_finishConnect")        { pPhase2 == 1 && pPhase2.becomes(2) }
            Action("p2_failConnect")          { pPhase2 == 1 && pPhase2.becomes(0) }
            Action("p2_disconnect")           { (pPhase2 == 2 || pPhase2 == 4 || pPhase2 == 6) && pPhase2.becomes(7) }
            Action("p2_finishDisconnect")     { pPhase2 == 7 && pPhase2.becomes(0) }
            Action("p2_beginDiscover")        { pPhase2 == 2 && pPhase2.becomes(3) }
            Action("p2_finishDiscover")       { pPhase2 == 3 && pPhase2.becomes(4) }
            Action("p2_beginDiscoverChars")   { pPhase2 == 4 && pPhase2.becomes(5) }
            Action("p2_finishDiscoverChars")  { pPhase2 == 5 && pPhase2.becomes(6) }

            Action("p3_beginConnect")         { pPhase3 == 0 && pPhase3.becomes(1) }
            Action("p3_finishConnect")        { pPhase3 == 1 && pPhase3.becomes(2) }
            Action("p3_failConnect")          { pPhase3 == 1 && pPhase3.becomes(0) }
            Action("p3_disconnect")           { (pPhase3 == 2 || pPhase3 == 4 || pPhase3 == 6) && pPhase3.becomes(7) }
            Action("p3_finishDisconnect")     { pPhase3 == 7 && pPhase3.becomes(0) }
            Action("p3_beginDiscover")        { pPhase3 == 2 && pPhase3.becomes(3) }
            Action("p3_finishDiscover")       { pPhase3 == 3 && pPhase3.becomes(4) }
            Action("p3_beginDiscoverChars")   { pPhase3 == 4 && pPhase3.becomes(5) }
            Action("p3_finishDiscoverChars")  { pPhase3 == 5 && pPhase3.becomes(6) }

            // Cross-actor invariants
            Invariant("noPeripheralWithoutPower") {
                ((cPhase == 5) || (pPhase1 == 0) || (pPhase1 == 7)) &&
                ((cPhase == 5) || (pPhase2 == 0) || (pPhase2 == 7)) &&
                ((cPhase == 5) || (pPhase3 == 0) || (pPhase3 == 7))
            }
            Invariant("noScanWhileConnecting") {
                ((cPhase != 6) || (pPhase1 != 1)) &&
                ((cPhase != 6) || (pPhase2 != 1)) &&
                ((cPhase != 6) || (pPhase3 != 1))
            }
            Invariant("poweredOffDisconnects") {
                ((cPhase != 4) || (pPhase1 == 0) || (pPhase1 == 7)) &&
                ((cPhase != 4) || (pPhase2 == 0) || (pPhase2 == 7)) &&
                ((cPhase != 4) || (pPhase3 == 0) || (pPhase3 == 7))
            }
            Invariant("resettingDisconnects") {
                ((cPhase != 1) || (pPhase1 != 6)) &&
                ((cPhase != 1) || (pPhase2 != 6)) &&
                ((cPhase != 1) || (pPhase3 != 6))
            }
        }
    }
}
