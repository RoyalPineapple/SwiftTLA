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

            // Central: 0=unknown 1=resetting 2=unsupported 3=unauthorized 4=poweredOff 5=poweredOn 6=scanning
            Action("cToPoweredOn")   { (cPhase == 0/*unknown*/ || cPhase == 1/*resetting*/ || cPhase == 4/*poweredOff*/) && cPhase.becomes(5/*poweredOn*/) }
            Action("cToPoweredOff")  { (cPhase == 0/*unknown*/ || cPhase == 1/*resetting*/ || cPhase == 5/*poweredOn*/) && cPhase.becomes(4/*poweredOff*/) }
            Action("cToUnsupported") { cPhase == 0/*unknown*/ && cPhase.becomes(2/*unsupported*/) }
            Action("cToUnauthorized") { cPhase == 0/*unknown*/ && cPhase.becomes(3/*unauthorized*/) }
            Action("cToResetting")   { (cPhase == 4/*poweredOff*/ || cPhase == 5/*poweredOn*/) && cPhase.becomes(1/*resetting*/) }
            Action("cStartScan")     { cPhase == 5/*poweredOn*/ && cPhase.becomes(6/*scanning*/) }
            Action("cStopScan")      { cPhase == 6/*scanning*/ && cPhase.becomes(5/*poweredOn*/) }

            // Peripheral: 0=disconnected 1=connecting 2=connected 3=discoveringServices
            // 4=servicesDiscovered 5=discoveringChars 6=ready 7=disconnecting
            for i in 1...3 {
                let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                Action("p\(i)_beginConnect")         { pVar == 0/*disconnected*/ && pVar.becomes(1/*connecting*/) }
                Action("p\(i)_finishConnect")        { pVar == 1/*connecting*/ && pVar.becomes(2/*connected*/) }
                Action("p\(i)_failConnect")          { pVar == 1/*connecting*/ && pVar.becomes(0/*disconnected*/) }
                Action("p\(i)_disconnect")           { (pVar == 2/*connected*/ || pVar == 4/*servicesDiscovered*/ || pVar == 6/*ready*/) && pVar.becomes(7/*disconnecting*/) }
                Action("p\(i)_finishDisconnect")     { pVar == 7/*disconnecting*/ && pVar.becomes(0/*disconnected*/) }
                Action("p\(i)_beginDiscover")        { pVar == 2/*connected*/ && pVar.becomes(3/*discoveringServices*/) }
                Action("p\(i)_finishDiscover")       { pVar == 3/*discoveringServices*/ && pVar.becomes(4/*servicesDiscovered*/) }
                Action("p\(i)_beginDiscoverChars")   { pVar == 4/*servicesDiscovered*/ && pVar.becomes(5/*discoveringChars*/) }
                Action("p\(i)_finishDiscoverChars")  { pVar == 5/*discoveringChars*/ && pVar.becomes(6/*ready*/) }
            }

            // Cross-actor invariants
            Invariant("noPeripheralWithoutPower") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase == 5/*poweredOn*/) || (pVar == 0/*disconnected*/) || (pVar == 7/*disconnecting*/)
                }
            }
            Invariant("noScanWhileConnecting") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase != 6/*scanning*/) || (pVar != 1/*connecting*/)
                }
            }
            Invariant("poweredOffDisconnects") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase != 4/*poweredOff*/) || (pVar == 0/*disconnected*/) || (pVar == 7/*disconnecting*/)
                }
            }
            Invariant("resettingDisconnects") {
                for i in 1...3 {
                    let pVar = [pPhase1, pPhase2, pPhase3][i-1]
                    (cPhase != 1/*resetting*/) || (pVar != 6/*ready*/)
                }
            }
        }
    }
}
