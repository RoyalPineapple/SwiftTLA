import Foundation
import SwiftTLA

package enum OrderedRHSCFGProof {
    package static func render(
        for rendered: RenderedSpecification, catalog: StraightLineRenderedActionCheck.FiniteActionCatalog,
        actionProofModule: String
    ) -> (name: String, bytes: Data)? {
        guard actionProofModule.range(of: "^[A-Za-z_][A-Za-z_0-9]*$", options: .regularExpression) != nil,
              let selection = normalSelection(for: rendered) else { return nil }
        let checking = selection.checking
        let catalogProof = catalog.proofSource(prefix: "SwiftTLAOrderedRHS")
        let name = "SwiftTLAOrderedRHSConfiguredProof"
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(actionProofModule), CallerInputPageBlock1

        \#(selection.proof)

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

        \#(catalogProof.dispatch)
        \#(catalogProof.body)

        RHSConfiguredCatalogSteps == \E label : SwiftTLAOrderedRHSEmittedLabeled(label)
        RHSConfiguredCatalogStuttering ==
            RHSConfiguredCatalogSteps \/ SwiftTLAOrderedRHSActualFrameAfter = SwiftTLAOrderedRHSActualFrameBefore
        RHSConfiguredCatalogBehavior == Init /\ [][RHSConfiguredCatalogSteps]_vars

        THEOREM ConfiguredArithmeticUsesTheCompleteLabeledActionCatalog ==
            /\ LocalOrderedRHSActualCFG = LocalOrderedRHSExpectedCFG
            /\ (Next <=> RHSConfiguredCatalogSteps)
            /\ ([Next]_vars <=> RHSConfiguredCatalogStuttering)
            /\ (Spec <=> RHSConfiguredCatalogBehavior)
            /\ (RHSOutputStateType => (RHSOutputSelectedEvaluationCheck <=> RHSOutputActualFailures = {}))
        PROOF
        <1>union. (\E SwiftTLAOrderedRHSIndex \in DOMAIN SwiftTLAOrderedRHSActualActionValues : SwiftTLAOrderedRHSActualActionValues[SwiftTLAOrderedRHSIndex])
                      <=> RHSConfiguredCatalogSteps
            BY ONLY SwiftTLAOrderedRHSActualNextUsesTheCompleteLabeledActionCatalog,
                SwiftTLAOrderedRHSDispatch!CatalogLabeledBranchesComposeTheFiniteUnion, SMT
                DEF RHSConfiguredCatalogSteps, SwiftTLAOrderedRHSEmittedLabeled
        <1>next. Next <=> RHSConfiguredCatalogSteps
            BY ONLY <1>union, SwiftTLAOrderedRHSActualNextUsesTheCompleteLabeledActionCatalog, PTL
        <1>stuttering. [Next]_vars <=> RHSConfiguredCatalogStuttering
            BY ONLY <1>union, SwiftTLAOrderedRHSActualNextUsesTheCompleteLabeledActionCatalog, PTL
                DEF RHSConfiguredCatalogStuttering
        <1>always. ([][Next]_vars) <=> ([][RHSConfiguredCatalogSteps]_vars)
            BY ONLY <1>next, PTL
        <1>behavior. Spec <=> RHSConfiguredCatalogBehavior
            BY ONLY <1>always, PTL DEF RHSConfiguredCatalogBehavior, Spec, vars
        <1>. QED BY ONLY <1>next, <1>stuttering, <1>behavior, NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking,
            ConfiguredEvaluationCheckMatchesTheCompleteSelectedRHSFailure, PTL

        ====

        """#
        return (name, Data(proof.utf8))
    }

    /// Uses the same emitted CFG grammar and caller-byte proof as the single-action case.
    static func renderCatalog(
        for rendered: RenderedSpecification, catalogModule: String, prefix: String, counter: String,
        actions: [(instance: String, failureOperator: String?)]
    ) -> (name: String, bytes: Data)? {
        guard let selection = normalSelection(for: rendered), let last = actions.last else { return nil }
        let name = catalogModule + "ConfiguredProof"
        let checking = selection.checking
        let continuations = actions.map {
            #"/\ \#($0.instance)!RHSOutputExit = \#($0.instance)!RHSOutputAuthoredExit"#
        }.joined(separator: "\n    ")
        let continuationTheorems = actions.map {
            "\($0.instance)!ActualSelectedActionUsesTheAuthoredContinuation"
        }.joined(separator: ", ")
        let failureSelectors = actions.map { "\($0.instance)!RHSOutputFailureSelected" }
        let observedFailures = actions.map { "\($0.instance)!RHSOutputActualFailures" }
        let localSelectors = failureSelectors.joined(separator: ", ")
        let failureDisjunction = failureSelectors.joined(separator: #" \/ "#)
        let selectorFacts = zip(failureSelectors, observedFailures).map {
            #"/\ \#($0.0) = (\#($0.1) # {})"#
        }.joined(separator: "\n        ")
        let noFailures = observedFailures.map { "\($0) = {}" }.joined(separator: #" /\ "#)
        let observations = actions.map { "\($0.instance)!RHSOutputHistoryObservation" }.joined(separator: ", ")
        let failureBindings = actions.enumerated().compactMap { index, action -> (fact: String, proof: String)? in
            guard let operatorName = action.failureOperator else { return nil }
            let fact = "<1>failureOperator\(index + 1)"
            let qualified = "\(action.instance)!\(operatorName)"
            let proof = #"""
            \#(fact). \#(operatorName) <=> \#(qualified)
                BY ONLY DEF \#(operatorName), \#(qualified)
            """#
            return (fact, proof)
        }
        let bindings = failureBindings.map(\.proof).joined(separator: "\n")
        let selectorSupport = (failureBindings.map(\.fact) + ["PTL"]).joined(separator: ", ")
        let terminal = actions.count + 1
        let before = (actions + [last]).map { "<<\(counter), \($0.instance)!RHSOutputBefore>>" }.joined(separator: ", ")
        let sendProofs = actions.enumerated().map { index, action in
            let slot = index + 1
            return #"""
            <2>send\#(slot). \#(prefix)PublicSendUsesCertifiedOutput(histories, \#(slot))
                <3>. DEFINE output == \#(prefix)NativeOrderedOutputs[\#(slot)]
                            certified == \#(prefix)CertifiedOrderedOutputs(histories)[\#(slot)]
                            before == \#(prefix)SendBefore[\#(slot)]
                            handle == NativeActionRoutes[\#(slot)].handle
                            final == histories[\#(slot)][\#(action.instance)!RHSOutputCount]
                            snapshots == {<<\#(action.instance)!RHSOutputExit, final.bindings>>}
                            reasons == \#(action.instance)!RHSOutputInput!Rule!ArithmeticFailures
                <3>route. SendSlot(handle) = \#(slot)
                    BY ONLY <1>sendRoute, SMT DEF handle, NativeActionRoutes
                <3>bindings. DecodedSendOperands(CatalogSendBinding, handle)
                    BY ONLY <1>sendBindings, SMT DEF handle, NativeActionRoutes
                <3>receipt.
                    /\ output = certified
                    /\ output.callbacks \in Seq(snapshots)
                    /\ output.reasons \in Seq(reasons)
                    /\ <<>> \notin reasons
                    BY ONLY <2>histories, IsaM("simp"), SMT DEF \#(prefix)NativeOrderedOutputsHold,
                        NativeOrderedOutputHolds\#(slot), \#(prefix)NativeOrderedOutputs, \#(prefix)CertifiedOrderedOutputs,
                        \#(action.instance)!RHSOutputInput!Rule!NativeAssignmentOrderedOutputsTyped,
                        output, certified, final, snapshots, reasons
                <3>run. DecodedPublicSend(CatalogSendBinding, before, handle, output.callbacks, output.reasons) =
                        PublicSendOutcome(CatalogSendBinding, before, handle, output.callbacks, output.reasons)
                    BY ONLY <3>bindings, <3>receipt, DecodedSendUsesTheFirstErrorOrCommitsExactlyOneCallback, SMT
                <3>. QED BY ONLY <3>run, <3>receipt, <3>route, SMT DEF \#(prefix)PublicSendUsesCertifiedOutput,
                    \#(prefix)NativePublicSend, output, certified, before, handle
            """#
        }.joined(separator: "\n    ")
        let sendFacts = (1...terminal).map { "<2>send\($0)" }.joined(separator: ", ")
        let sendCases = (1...terminal).map { "slot = \($0)" }.joined(separator: #" \/ "#)
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(catalogModule), CallerInputPageBlock1, \#(catalogModule)SendBinding

        \#(selection.proof)

        \#(prefix)ConfiguredSteps == \E label : \#(prefix)EmittedLabeled(label)
        \#(prefix)ConfiguredBehavior == Init /\ [][\#(prefix)ConfiguredSteps]_vars
        \#(prefix)SelectedEvaluationCheck == \#(checking)
        \#(prefix)ConfiguredContinuations ==
            \#(continuations)

        LOCAL AuthoredSlots == DOMAIN \#(prefix)NativeSelectedSteps
        LOCAL AuthoredRoutes == [slot \in AuthoredSlots |-> NativeActionRoutes[slot]]
        LOCAL AuthoredFormal == [slot \in AuthoredSlots |-> \#(prefix)ActualFormalLabels[slot]]
        LOCAL AuthoredLabels == [slot \in AuthoredSlots |-> \#(prefix)ActualAuthoredLabels[slot]]
        LOCAL NoAuthoredFailures(failures) == \A slot \in DOMAIN failures : failures[slot] = {}
        LOCAL \#(prefix)SendBefore == <<\#(before)>>
        LOCAL SendSlots == AuthoredSlots \cup {\#(terminal)}
        LOCAL SendSlot(action) == DecodedSendReceiver(CatalogSendBinding, action).visitor

        \#(prefix)NativePublicSend(action) ==
            LET slot == SendSlot(action)
                output == IF slot = \#(terminal) THEN NativeTerminalOrderedOutput ELSE \#(prefix)NativeOrderedOutputs[slot]
            IN DecodedPublicSend(CatalogSendBinding, \#(prefix)SendBefore[slot],
                action, output.callbacks, output.reasons)

        \#(prefix)PublicSendUsesCertifiedOutput(histories, slot) ==
            LET output == IF slot = \#(terminal) THEN CertifiedTerminalOrderedOutput
                         ELSE \#(prefix)CertifiedOrderedOutputs(histories)[slot]
            IN \#(prefix)NativePublicSend(NativeActionRoutes[slot].handle) =
                PublicSendOutcome(CatalogSendBinding, \#(prefix)SendBefore[slot],
                    NativeActionRoutes[slot].handle, output.callbacks, output.reasons)

        \#(prefix)NativeAuthoredLabeled(label) ==
            \#(prefix)Dispatch!NativeDispatchLabeled(AuthoredRoutes, \#(prefix)NativeSelectedSteps,
                AuthoredFormal, AuthoredLabels, label)
        \#(prefix)CertifiedAuthoredLabeled(histories, label) ==
            \#(prefix)Dispatch!CatalogLabeledBranches(\#(prefix)CertifiedActions(histories), AuthoredLabels, label)

        THEOREM ConfiguredAssignmentCatalogUsesTheCertifiedHistories ==
            /\ LocalOrderedRHSActualCFG = LocalOrderedRHSExpectedCFG
            /\ (Next <=> \#(prefix)ConfiguredSteps)
            /\ (Spec <=> \#(prefix)ConfiguredBehavior)
            /\ \#(prefix)ConfiguredContinuations
            /\ (\#(prefix)InputType => \E histories :
                /\ \#(prefix)HistoriesHold(histories)
                /\ (Next <=> \#(prefix)CertifiedNext(histories))
                /\ \A label : \#(prefix)EmittedLabeled(label) <=> \#(prefix)CertifiedLabeled(histories, label)
                /\ \A label : \#(prefix)NativeAuthoredLabeled(label) <=> \#(prefix)CertifiedAuthoredLabeled(histories, label)
                /\ SendSlots = DOMAIN NativeActionRoutes
                /\ \A slot \in SendSlots : \#(prefix)PublicSendUsesCertifiedOutput(histories, slot)
                /\ (\#(prefix)SelectedEvaluationCheck <=> NoAuthoredFailures(\#(prefix)CertifiedFailures(histories)))
                /\ (\#(prefix)SelectedEvaluationCheck <=> NoAuthoredFailures(\#(prefix)NativeSelectedFailures)))
        PROOF
        <1>union. (\E \#(prefix)Index \in DOMAIN \#(prefix)ActualActionValues : \#(prefix)ActualActionValues[\#(prefix)Index])
                      <=> \#(prefix)ConfiguredSteps
            BY ONLY \#(prefix)ActualNextUsesTheCompleteLabeledActionCatalog,
                \#(prefix)Dispatch!CatalogLabeledBranchesComposeTheFiniteUnion, SMT
                DEF \#(prefix)ConfiguredSteps, \#(prefix)EmittedLabeled
        <1>next. Next <=> \#(prefix)ConfiguredSteps
            BY ONLY <1>union, \#(prefix)ActualNextUsesTheCompleteLabeledActionCatalog, PTL
        <1>always. ([][Next]_vars) <=> ([][\#(prefix)ConfiguredSteps]_vars)
            BY ONLY <1>next, PTL
        <1>behavior. Spec <=> \#(prefix)ConfiguredBehavior
            BY ONLY <1>always, PTL DEF \#(prefix)ConfiguredBehavior, Spec, vars
        \#(bindings)
        <1>selector. \#(prefix)SelectedEvaluationCheck <=> ~(\#(failureDisjunction))
            BY ONLY \#(selectorSupport) DEF \#(prefix)SelectedEvaluationCheck, \#(checking), \#(localSelectors)
        <1>routes. \#(prefix)Dispatch!NativeDispatchBindsTheActionCatalog(AuthoredRoutes, AuthoredFormal)
            BY ONLY SMT DEF AuthoredSlots, AuthoredRoutes, AuthoredFormal, NativeActionRoutes,
                \#(prefix)NativeSelectedSteps, \#(prefix)ActualFormalLabels, \#(prefix)ActualActionRoutes,
                \#(prefix)Dispatch!NativeDispatchBindsTheActionCatalog
        <1>labelDomain. DOMAIN AuthoredLabels = DOMAIN AuthoredFormal
            BY ONLY SMT DEF AuthoredLabels, AuthoredFormal
        <1>sendDomain. SendSlots = DOMAIN NativeActionRoutes
            BY ONLY IsaM("simp"), SMT DEF SendSlots, AuthoredSlots, \#(prefix)NativeSelectedSteps, NativeActionRoutes
        <1>sendVisitors. DecodedSendRoutesMatch(CatalogSendBinding, NativeActionRoutes)
            BY ONLY CatalogSendBindingReceivers, SMT DEF DecodedSendRoutesMatch, NativeActionRoutes
        <1>sendRoute. \A slot \in DOMAIN NativeActionRoutes : SendSlot(NativeActionRoutes[slot].handle) = slot
            <2>ordinal. \A slot \in DOMAIN NativeActionRoutes : NativeActionRoutes[slot].visitor = slot
                BY ONLY SMT DEF NativeActionRoutes
            <2>. QED BY ONLY <1>sendVisitors, <2>ordinal, DecodedSendReceiverUsesMatchedVisitor, SMT DEF SendSlot
        <1>sendBindings. \A slot \in DOMAIN NativeActionRoutes :
            DecodedSendOperands(CatalogSendBinding, NativeActionRoutes[slot].handle)
            BY ONLY CatalogSendBindingDecodesReceiverOperands, SMT DEF NativeActionRoutes
        <1>typed. ASSUME \#(prefix)InputType
            PROVE \E histories :
                /\ \#(prefix)HistoriesHold(histories)
                /\ (Next <=> \#(prefix)CertifiedNext(histories))
                /\ \A label : \#(prefix)NativeAuthoredLabeled(label) <=> \#(prefix)CertifiedAuthoredLabeled(histories, label)
                /\ SendSlots = DOMAIN NativeActionRoutes
                /\ \A slot \in SendSlots : \#(prefix)PublicSendUsesCertifiedOutput(histories, slot)
                /\ (\#(prefix)SelectedEvaluationCheck <=> NoAuthoredFailures(\#(prefix)CertifiedFailures(histories)))
                /\ (\#(prefix)SelectedEvaluationCheck <=> NoAuthoredFailures(\#(prefix)NativeSelectedFailures))
                /\ \A label : \#(prefix)EmittedLabeled(label) <=> \#(prefix)CertifiedLabeled(histories, label)
            <2>histories. PICK histories :
                /\ \#(prefix)HistoriesHold(histories)
                /\ (Next <=> \#(prefix)CertifiedNext(histories))
                /\ \A label : \#(prefix)EmittedLabeled(label) <=> \#(prefix)CertifiedLabeled(histories, label)
                /\ \A slot \in AuthoredSlots :
                    \#(prefix)NativeSelectedSteps[slot] <=> \#(prefix)CertifiedActions(histories)[slot]
                /\ \#(prefix)NativeSelectedFailures = \#(prefix)ActualFailures
                /\ \#(prefix)ActualFailures = \#(prefix)CertifiedFailures(histories)
                /\ \#(prefix)NativeOrderedOutputsHold(histories)
                BY ONLY \#(prefix)InputType, ActualNextAndFailuresUseTheCertifiedAssignmentHistories,
                    SMT DEF AuthoredSlots
            <2>points. \A slot \in DOMAIN AuthoredFormal :
                \#(prefix)NativeSelectedSteps[slot] <=> \#(prefix)CertifiedActions(histories)[slot]
                BY ONLY <2>histories, SMT DEF AuthoredFormal
            <2>labels. \A label : \#(prefix)NativeAuthoredLabeled(label) <=>
                                  \#(prefix)CertifiedAuthoredLabeled(histories, label)
                BY ONLY <1>routes, <1>labelDomain, <2>points,
                    \#(prefix)Dispatch!CertifiedNativeDispatchUsesTheLabeledCatalog, SMT
                    DEF \#(prefix)NativeAuthoredLabeled, \#(prefix)CertifiedAuthoredLabeled
            <2>predicates.
                \#(selectorFacts)
                BY ONLY <2>histories DEF \#(prefix)HistoriesHold, \#(observations)
            <2>physical. NoAuthoredFailures(\#(prefix)ActualFailures) <=> (\#(noFailures))
                BY ONLY IsaM("simp"), SMT DEF NoAuthoredFailures, \#(prefix)ActualFailures
            <2>checking. \#(prefix)SelectedEvaluationCheck <=> NoAuthoredFailures(\#(prefix)ActualFailures)
                BY ONLY <1>selector, <2>predicates, <2>physical, SMT
            \#(sendProofs)
            <2>send\#(terminal). \#(prefix)PublicSendUsesCertifiedOutput(histories, \#(terminal))
                <3>. DEFINE output == NativeTerminalOrderedOutput
                            before == \#(prefix)SendBefore[\#(terminal)]
                            handle == NativeActionRoutes[\#(terminal)].handle
                            snapshots == {<<\#(counter), \#(last.instance)!RHSOutputBefore>>}
                <3>route. SendSlot(handle) = \#(terminal)
                    BY ONLY <1>sendRoute, SMT DEF handle, NativeActionRoutes
                <3>binding. DecodedSendOperands(CatalogSendBinding, handle)
                    BY ONLY <1>sendBindings, SMT DEF handle, NativeActionRoutes
                <3>receipt.
                    /\ output = CertifiedTerminalOrderedOutput
                    /\ output.callbacks \in Seq(snapshots)
                    /\ output.reasons \in Seq({})
                    BY ONLY \#(prefix)InputType, NativeTerminalOrderedOutputUsesTheCompleteFrame, SMT
                        DEF output, snapshots
                <3>run. DecodedPublicSend(CatalogSendBinding, before, handle, output.callbacks, output.reasons) =
                        PublicSendOutcome(CatalogSendBinding, before, handle, output.callbacks, output.reasons)
                    BY ONLY <3>binding, <3>receipt, DecodedSendUsesTheFirstErrorOrCommitsExactlyOneCallback, SMT
                <3>. QED BY ONLY <3>run, <3>receipt, <3>route, SMT DEF \#(prefix)PublicSendUsesCertifiedOutput,
                    \#(prefix)NativePublicSend, output, before, handle
            <2>sendSlots. \A slot \in SendSlots : \#(sendCases)
                BY ONLY IsaM("simp"), SMT DEF SendSlots, AuthoredSlots, \#(prefix)NativeSelectedSteps
            <2>send. \A slot \in SendSlots : \#(prefix)PublicSendUsesCertifiedOutput(histories, slot)
                BY ONLY <2>sendSlots, \#(sendFacts), SMT
            <2>. WITNESS histories
            <2>. QED BY ONLY <2>histories, <2>labels, <2>checking, <1>sendDomain, <2>send, SMT
        <1>continuations. \#(prefix)ConfiguredContinuations
            BY ONLY \#(continuationTheorems) DEF \#(prefix)ConfiguredContinuations
        <1>. QED BY ONLY NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking,
            <1>next, <1>behavior, <1>continuations, <1>typed, Zenon

        ====

        """#
        return (name, Data(proof.utf8))
    }

    private static func normalSelection(for rendered: RenderedSpecification) -> (checking: String, proof: String)? {
        guard let cfg = rendered.tlaBundle.root.cfg else { return nil }
        return normalSelection(cfg: cfg, intrinsicInvariants: rendered.intrinsicInvariantNames)
    }

    static func normalSelection(cfg: String, intrinsicInvariants: Set<String>) -> (checking: String, proof: String)? {
        let lines = cfg.split(separator: "\n")
        let invariant = "INVARIANT __SwiftTLAEvaluationOK"
        guard lines.count == 3, lines[0] == "SPECIFICATION Spec", lines[1] == "CHECK_DEADLOCK TRUE",
              lines[2].hasPrefix(invariant), lines[2].dropFirst(invariant.count).allSatisfy({ $0 == "_" }),
              cfg.utf8.elementsEqual((lines.joined(separator: "\n") + "\n").utf8) else { return nil }
        let checking = lines[2].dropFirst("INVARIANT ".count)
        guard intrinsicInvariants == [String(checking)] else { return nil }
        return (String(checking), selectionProof(cfg: cfg, theorem: "NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking"))
    }

    static func normalTotalSelection(cfg: String, intrinsicInvariants: Set<String>) -> String? {
        guard intrinsicInvariants.isEmpty,
              cfg.utf8.elementsEqual("SPECIFICATION Spec\nCHECK_DEADLOCK TRUE\n".utf8) else { return nil }
        return selectionProof(cfg: cfg, theorem: "NormalOrderedRHSCFGSelectsSpecAndDeadlock")
    }

    private static func selectionProof(cfg: String, theorem: String) -> String {
        let expected = "<<\(cfg.utf8.map(String.init).joined(separator: ", "))>>"
        let pages = (1...((cfg.utf8.count + 15) / 16)).map { "CallerInputPage\($0)" }.joined(separator: " ")
        return #"""
        \* \#(pages)
        LocalOrderedRHSActualCFG == [byte \in 1..CallerInputSize |-> CallerInputByte[byte - 1]]
        LocalOrderedRHSExpectedCFG == \#(expected)

        THEOREM \#(theorem) ==
            LocalOrderedRHSActualCFG = LocalOrderedRHSExpectedCFG
        PROOF
        <1>domain. DOMAIN LocalOrderedRHSActualCFG = DOMAIN LocalOrderedRHSExpectedCFG
            BY SMT DEF LocalOrderedRHSActualCFG, LocalOrderedRHSExpectedCFG, CallerInputSize
        <1>bytes. \A byte \in DOMAIN LocalOrderedRHSExpectedCFG :
            LocalOrderedRHSActualCFG[byte] = LocalOrderedRHSExpectedCFG[byte]
            BY ONLY CallerInputPageBlock1AtFileOffsets, SMT
                DEF LocalOrderedRHSActualCFG, LocalOrderedRHSExpectedCFG, CallerInputSize
        <1>. QED BY <1>domain, <1>bytes, SMT DEF LocalOrderedRHSActualCFG, LocalOrderedRHSExpectedCFG
        """#
    }
}
