import Foundation
import SwiftTLA

package enum OrderedRHSCFGProof {
    package static func render(
        for rendered: RenderedSpecification, actionProofModule: String = "SwiftTLAOrderedRHSOutputProof"
    ) -> (name: String, bytes: Data)? {
        guard actionProofModule.range(of: "^[A-Za-z_][A-Za-z_0-9]*$", options: .regularExpression) != nil,
              let cfg = rendered.tlaBundle.root.cfg else { return nil }
        let lines = cfg.split(separator: "\n")
        let invariant = "INVARIANT __SwiftTLAEvaluationOK"
        guard lines.count == 3, lines[0] == "SPECIFICATION Spec", lines[1] == "CHECK_DEADLOCK TRUE",
              lines[2].hasPrefix(invariant), lines[2].dropFirst(invariant.count).allSatisfy({ $0 == "_" }),
              cfg.utf8.elementsEqual((lines.joined(separator: "\n") + "\n").utf8) else { return nil }
        let checking = lines[2].dropFirst("INVARIANT ".count)
        let expected = "<<\(cfg.utf8.map(String.init).joined(separator: ", "))>>"
        let pages = (1...((cfg.utf8.count + 15) / 16)).map { "CallerInputPage\($0)" }.joined(separator: " ")
        let name = "SwiftTLAOrderedRHSConfiguredProof"
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(actionProofModule), CallerInputPageBlock1

        \* \#(pages)
        LocalOrderedRHSActualCFG == [byte \in 1..CallerInputSize |-> CallerInputByte[byte - 1]]
        LocalOrderedRHSExpectedCFG == \#(expected)

        THEOREM NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking ==
            LocalOrderedRHSActualCFG = LocalOrderedRHSExpectedCFG
        PROOF
        <1>domain. DOMAIN LocalOrderedRHSActualCFG = DOMAIN LocalOrderedRHSExpectedCFG
            BY SMT DEF LocalOrderedRHSActualCFG, LocalOrderedRHSExpectedCFG, CallerInputSize
        <1>bytes. \A byte \in DOMAIN LocalOrderedRHSExpectedCFG :
            LocalOrderedRHSActualCFG[byte] = LocalOrderedRHSExpectedCFG[byte]
            BY ONLY CallerInputPageBlock1AtFileOffsets, SMT
                DEF LocalOrderedRHSActualCFG, LocalOrderedRHSExpectedCFG, CallerInputSize
        <1>. QED BY <1>domain, <1>bytes, SMT DEF LocalOrderedRHSActualCFG, LocalOrderedRHSExpectedCFG

        RHSOutputSelectedEvaluationCheck == \#(checking)

        THEOREM ConfiguredEvaluationCheckMatchesTheCompleteSelectedRHSFailure ==
            ASSUME RHSOutputStateType
            PROVE RHSOutputSelectedEvaluationCheck <=> RHSOutputActualFailures = {}
        PROOF
        <1>selector. RHSOutputSelectedEvaluationCheck <=> ~RHSOutputFailureSelected
            BY SMT DEF RHSOutputSelectedEvaluationCheck, \#(checking), RHSOutputFailureSelected
        <1>observation. RHSOutputFailureSelected = (RHSOutputActualFailures # {})
            BY RHSOutputStateType, ActualTLAActionHasACertifiedAssignmentHistory, SMT
                DEF RHSOutputHistoryObservation
        <1>. QED BY <1>selector, <1>observation, SMT

        ====

        """#
        return (name, Data(proof.utf8))
    }
}
