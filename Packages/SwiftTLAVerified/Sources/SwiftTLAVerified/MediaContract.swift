import SwiftTLA
import SwiftTLAMacros

/// Cross-actor proof: Capture + Writer + Player composition.
/// Proves WriterRequiresCapture and PlayerRequiresWriter at compile time.
/// Individual actors (Media.Capture, Media.Writer, Media.Player) exist for
/// standalone use.  MediaContract proves they compose correctly.
@TLAActor
public actor MediaContract {
    public static var spec: TLASpec {
        TLASpec("MediaContract") {
            let cPhase = Var<Int>("cPhase")
            let wPhase = Var<Int>("wPhase")
            let pPhase = Var<Int>("pPhase")

            Variable(cPhase, 0); Variable(wPhase, 0); Variable(pPhase, 0)

            Action("cConfigure")  { cPhase == 0 && cPhase.becomes(1) }
            Action("cStart")      { cPhase == 1 && cPhase.becomes(2) }
            Action("cStop")       { (cPhase == 2 || cPhase == 3) && (wPhase != 2 && wPhase != 3) && cPhase.becomes(0) }
            Action("cInterrupt")  { cPhase == 2 && (wPhase != 2 && wPhase != 3) && cPhase.becomes(3) }
            Action("cResume")     { cPhase == 3 && cPhase.becomes(2) }

            Action("wConfigure")  { wPhase == 0 && wPhase.becomes(1) }
            Action("wStart")      { wPhase == 1 && cPhase == 2 && wPhase.becomes(2) }
            Action("wRecord")     { wPhase == 2 && wPhase.stays }
            Action("wPause")      { wPhase == 2 && wPhase.becomes(3) }
            Action("wResume")     { wPhase == 3 && wPhase.becomes(2) }
            Action("wFinish")     { wPhase == 1 && wPhase.becomes(4) }
            Action("wCancel")     { (wPhase == 2 || wPhase == 3) && wPhase.becomes(5) }

            Action("pLoad")       { pPhase == 0 && pPhase.becomes(1) }
            Action("pReady")      { pPhase == 1 && pPhase.becomes(2) }
            Action("pPlay")       { (pPhase == 2 || pPhase == 4) && wPhase == 4 && pPhase.becomes(3) }
            Action("pPause")      { pPhase == 3 && pPhase.becomes(4) }
            Action("pFinish")     { pPhase == 3 && pPhase.becomes(5) }

            Invariant("writerRequiresCapture") { (wPhase != 2 && wPhase != 3) || (cPhase == 2) }
            Invariant("playerRequiresWriter")  { (pPhase != 3) || (wPhase == 4) }
        }
    }
}
