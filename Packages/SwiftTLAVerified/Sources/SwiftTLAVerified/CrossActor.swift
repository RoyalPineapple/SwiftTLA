import SwiftTLA
import SwiftTLAMacros

/// Cross-actor verification: Central + N Peripherals.
/// Proves no Peripheral is active while Central is powered off.
@TLAActor
public actor CrossActor {
    public static var spec: TLASpec {
        TLASpec("CrossActor") {
            let cPhase = Var<Int>("cPhase")
            let pPhase1 = Var<Int>("pPhase1")
            let pPhase2 = Var<Int>("pPhase2")
            let pPhase3 = Var<Int>("pPhase3")

            Variable(cPhase, 0)
            Variable(pPhase1, 0)
            Variable(pPhase2, 0)
            Variable(pPhase3, 0)

            // Central phases
            Action("cToPoweredOn")  { (cPhase == 0 || cPhase == 1 || cPhase == 4) && cPhase.becomes(5) }
            Action("cToPoweredOff") { (cPhase == 0 || cPhase == 1 || cPhase == 5) && cPhase.becomes(4) }
            Action("cToUnsupported") { cPhase == 0 && cPhase.becomes(2) }
            Action("cToUnauthorized") { cPhase == 0 && cPhase.becomes(3) }
            Action("cToResetting")  { (cPhase == 4 || cPhase == 5) && cPhase.becomes(1) }
            Action("cStartScan")    { cPhase == 5 && cPhase.becomes(6) }
            Action("cStopScan")     { cPhase == 6 && cPhase.becomes(5) }

            for i in 1...3 {
                let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                Action("p\(i)_beginConnect")  { pVar == 0 && pVar.becomes(1) }
                Action("p\(i)_finishConnect") { pVar == 1 && pVar.becomes(2) }
                Action("p\(i)_failConnect")   { pVar == 1 && pVar.becomes(0) }
                Action("p\(i)_disconnect")    { (pVar == 2 || pVar == 4 || pVar == 6) && pVar.becomes(7) }
                Action("p\(i)_finishDisconnect") { pVar == 7 && pVar.becomes(0) }
                Action("p\(i)_beginDiscover") { pVar == 2 && pVar.becomes(3) }
                Action("p\(i)_finishDiscover") { pVar == 3 && pVar.becomes(4) }
                Action("p\(i)_beginDiscoverChars") { pVar == 4 && pVar.becomes(5) }
                Action("p\(i)_finishDiscoverChars") { pVar == 5 && pVar.becomes(6) }
            }

            Invariant("noPeripheralWithoutPower") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase == 5) || (pVar == 0) || (pVar == 7)
                }
            }
            Invariant("noScanWhileConnecting") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase != 6) || (pVar != 1)
                }
            }
            Invariant("poweredOffDisconnects") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase != 4) || (pVar == 0) || (pVar == 7)
                }
            }
            Invariant("resettingDisconnects") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase != 1) || (pVar != 6)
                }
            }
        }
    }
}
