import Foundation
import SwiftTLA

extension ScalarCopyActionEvidence.Proof {
    func configuredBehavior(for rendered: RenderedSpecification) -> (name: String, bytes: Data)? {
        guard let cfg = rendered.tlaBundle.root.cfg,
              cfg.utf8.elementsEqual("SPECIFICATION Spec\nCHECK_DEADLOCK TRUE\n".utf8),
              rendered.tlaBundle.root.name != "NormalSeedCFG" else { return nil }
        let name = prefix + "ConfiguredBehavior"
        let reader = prefix + "CFG"
        let steps = prefix + "SelectedSourceSteps"
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(parentName)
        LOCAL \#(reader) == INSTANCE NormalSeedCFG
        \* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
        LOCAL \#(steps) == \E \#(prefix)Label : \#(prefix)SourceLabeled(\#(prefix)Label)

        THEOREM \#(prefix)NormalConfigurationSelectsTheSourceSteps ==
            /\ \#(reader)!ActualCFG = \#(reader)!SeedCFG
            /\ (Spec <=> (Init /\ [][\#(steps)]_vars))
        PROOF
        <1>step. Next <=> \#(steps)
            BY ONLY \#(prefix)ActualLabeledActionsAndNext DEF \#(steps)
        <1>stutter. [Next]_vars <=> [\#(steps)]_vars
            BY <1>step, PTL
        <1>behaviors. ([][Next]_vars) <=> ([][\#(steps)]_vars)
            BY <1>stutter, PTL
        <1>. QED BY \#(reader)!NormalCFGIsTheSpecAndDeadlockSelection, <1>behaviors, PTL DEF Spec
        ====

        """#
        return (name, Data(proof.utf8))
    }
}
