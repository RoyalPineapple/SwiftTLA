import Foundation
import SwiftTLA

extension ScalarCopyActionEvidence.Proof {
    func configuredBehavior(for rendered: RenderedSpecification, layout: CompiledLayout) -> (name: String, bytes: Data)? {
        guard let cfg = rendered.tlaBundle.root.cfg,
              cfg.utf8.elementsEqual("SPECIFICATION Spec\nCHECK_DEADLOCK TRUE\n".utf8),
              !["NormalSeedCFG", "SwiftTLANativeActions", "NativeScalarCopyRule", "OrderedScalarCopyRule"]
                .contains(rendered.tlaBundle.root.name) else { return nil }
        let actions = layout.actions.filter { !$0.isTermination }
        guard let terminal = layout.actions.last, terminal.isTermination,
              actions.count + 1 == layout.actions.count,
              Set(layout.actions.map(\.renderedName)).count == layout.actions.count else { return nil }

        let p = prefix
        let name = p + "ConfiguredBehavior"
        let rows = actions.indices.map { index in
            let n = index + 1
            return "[reads |-> \(p)Reads\(n), writes |-> \(p)Writes\(n), "
                + "entry |-> \(p)Entries[\(n)], control |-> <<\"control\", \(p)Destinations[\(n)]>>]"
        } + ["[reads |-> <<>>, writes |-> \(p)CopyRules!CopyEntryRoutes(\(p)Keys), "
            + "entry |-> \(p)TerminalControl, control |-> <<\"state\", \(p)NativeRules!NativeCopyControlSlot>>]"]
        let labels = TLAValue.tuple(layout.actions.map { .string($0.renderedName) })
        let compiled = actions.indices.map { "\(p)CompiledBranch\($0 + 1)" }.joined(separator: ", ")
        let receiptDefinitions = actions.indices.flatMap { index in
            ["\(p)Reads\(index + 1)", "\(p)Writes\(index + 1)", "\(p)CompiledBranch\(index + 1)"]
        }.joined(separator: ", ")
        let routeTheorems = actions.indices.map { "\(p)Row\($0 + 1)" }.joined(separator: ", ")
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(parentName), CompilerInputPageBlock1, Sequences
        LOCAL \#(p)CFG == INSTANCE NormalSeedCFG
        LOCAL \#(p)NativeRules == INSTANCE NativeScalarCopyRule
        LOCAL \#(p)CopyRules == INSTANCE OrderedScalarCopyRule
        LOCAL \#(p)Native == INSTANCE SwiftTLANativeActions

        \* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
        LOCAL \#(p)Receipts == <<\#(rows.joined(separator: ",\n    "))>>
        LOCAL \#(p)NativeRows == \#(p)Native!NativeActionRows
        LOCAL \#(p)RenderedLabels == \#(labels)
        LOCAL \#(p)AllSourceLabels == Append(\#(p)Labels, \#(p)TerminalLabel)
        LOCAL \#(p)NativePlan(index) ==
            \#(p)NativeRules!NativeCopyRekey(\#(p)NativeRows[index][2], \#(p)Keys, \#(p)FormalNames, \#(p)ControlKey)
        LOCAL \#(p)NativeBranch(index) ==
            \#(p)NativeRules!NativeCopyVisits(\#(p)NativePlan(index), \#(p)Keys,
                \#(p)Before, \#(p)After, \#(p)ControlBefore, \#(p)ControlAfter)
        LOCAL \#(p)CompiledBranches == <<\#(compiled), \#(p)SourceTermination>>
        LOCAL \#(p)SourceBranchAt(index) ==
            IF index \in DOMAIN \#(p)Labels THEN \#(p)SourceBranch(index) ELSE \#(p)SourceTermination

        \#(p)NativeLabeled(label) ==
            \E index \in DOMAIN \#(p)NativeRows :
                /\ \#(p)NativeBranch(index)
                /\ \E authored \in DOMAIN \#(p)RenderedLabels :
                    /\ \#(p)Native!NativeActionDispatchLabels[index] = \#(p)RenderedLabels[authored]
                    /\ \#(p)AllSourceLabels[authored] = label
        \#(p)NativeSteps == \E label : \#(p)NativeLabeled(label)
        \#(p)SelectedSourceSteps == \E label : \#(p)SourceLabeled(label)
        \#(p)SelectedBehavior == (\#(p)CFG!ActualCFG = \#(p)CFG!SeedCFG) /\ Spec

        THEOREM \#(p)ActualConfiguredCopyDispatchPreservesSteps ==
            /\ \#(p)CFG!ActualCFG = \#(p)CFG!SeedCFG
            /\ \A label : \#(p)NativeLabeled(label) <=> \#(p)SourceLabeled(label)
            /\ \A label : \#(p)NativeLabeled(label) <=> \#(p)EmittedLabeled(label)
            /\ (Next <=> \#(p)NativeSteps)
            /\ ([\#(p)NativeSteps]_vars <=> [\#(p)SelectedSourceSteps]_vars)
            /\ (\#(p)SelectedBehavior <=> (Init /\ [][\#(p)NativeSteps]_vars))
        PROOF
        <1>labels.
            /\ DOMAIN \#(p)NativeRows = DOMAIN \#(p)Receipts
            /\ DOMAIN \#(p)RenderedLabels = DOMAIN \#(p)NativeRows
            /\ DOMAIN \#(p)AllSourceLabels = DOMAIN \#(p)NativeRows
            /\ \A index, authored \in DOMAIN \#(p)NativeRows :
                  (\#(p)Native!NativeActionDispatchLabels[index] = \#(p)RenderedLabels[authored])
                        <=> (index = authored)
            /\ \A index \in DOMAIN \#(p)NativeRows :
                  \#(p)NativeRows[index][1] = \#(p)AllSourceLabels[index]
            /\ DOMAIN \#(p)Rows = DOMAIN \#(p)Labels
            /\ \A index \in DOMAIN \#(p)Labels : \#(p)Rows[index].label = \#(p)Labels[index]
            BY \#(p)ActualSourceLabelOrder, SMT
                DEF \#(p)NativeRows, \#(p)Native!NativeActionDispatchLabels, \#(p)Labels,
                    \#(p)TerminalLabel, \#(p)Receipts, \#(p)RenderedLabels, \#(p)AllSourceLabels
        <1>known. \A index \in DOMAIN \#(p)NativeRows :
            \#(p)NativeRules!NativeCopyKnownRoles(\#(p)NativeRows[index][2], \#(p)Keys,
                \#(p)FormalNames, \#(p)ControlKey)
            BY \#(p)ActualLayoutKeys, SMT
                DEF \#(p)NativeRules!NativeCopyKnownRoles, \#(p)NativeRules!NativeCopyPhysicalKeys,
                    \#(p)NativeRows, \#(p)FormalNames, \#(p)ControlKey
        <1>plans. \A index \in DOMAIN \#(p)NativeRows :
            LET receipt == \#(p)Receipts[index] IN
                \#(p)NativeRules!NativeCompleteCopyPlan(\#(p)NativePlan(index), \#(p)Keys,
                   receipt.reads, receipt.writes, receipt.entry, receipt.control)
            BY <1>labels, <1>known, \#(p)ActualLayoutKeys, SetExtensionality, SMT
                DEF \#(p)NativePlan, \#(p)NativeRows, \#(p)Receipts, \#(p)FormalNames, \#(p)ControlKey,
                    \#(p)NativeRules!NativeCopyKnownRoles, \#(p)NativeRules!NativeCopyKey,
                    \#(p)NativeRules!NativeCopyRekey, \#(p)NativeRules!NativeCompleteCopyPlan,
                    \#(p)NativeRules!NativeCopyFields, \#(p)NativeRules!NativeCopyControlSlot,
                    \#(p)CopyRules!CopyEntryRoutes, \#(p)Entries, \#(p)Destinations, \#(p)TerminalControl,
                    \#(receiptDefinitions)
        <1>physical. \A index \in DOMAIN \#(p)NativeRows :
            LET receipt == \#(p)Receipts[index] IN
                \#(p)NativeBranch(index) <=>
                    /\ \#(p)ControlBefore = receipt.entry
                    /\ \#(p)ControlAfter = (IF receipt.control[1] = "control"
                                               THEN receipt.control[2] ELSE \#(p)ControlBefore)
                    /\ \#(p)CopyRules!CompiledCopyBranch(\#(p)Keys, \#(p)Before, receipt.reads, receipt.writes, \#(p)After)
            BY <1>plans, \#(p)ActualLayoutKeys, \#(p)NativeRules!ValidatedNativeCopyPlansHaveTheCompleteCompiledObservation, SMT
                DEF \#(p)NativeBranch
        <1>terminal. \#(p)CopyRules!CompiledCopyBranch(\#(p)Keys, \#(p)Before,
            <<>>, \#(p)CopyRules!CopyEntryRoutes(\#(p)Keys), \#(p)After) <=> \#(p)Before = \#(p)After
            BY \#(p)ActualLayoutKeys, \#(p)NativeRules!EmptyCopyPlanRetainsTheCompleteState, SMT
        <1>compiled. \A index \in DOMAIN \#(p)NativeRows :
             \#(p)NativeBranch(index) <=> \#(p)CompiledBranches[index]
            BY <1>labels, <1>physical, <1>terminal, SMT
                DEF \#(p)Receipts, \#(p)CompiledBranches, \#(p)SourceTermination,
                    \#(p)NativeRules!NativeCopyControlSlot, \#(p)ControlBefore, \#(p)ControlAfter,
                    \#(receiptDefinitions)
        <1>source. \A index \in DOMAIN \#(p)NativeRows :
            \#(p)CompiledBranches[index] <=> \#(p)SourceBranchAt(index)
            BY <1>labels, \#(routeTheorems), SMT
                DEF \#(p)CompiledBranches, \#(p)SourceBranchAt, \#(p)Labels, \#(p)Receipts
        <1>dispatch. \A label : \#(p)NativeLabeled(label) <=> \#(p)SourceLabeled(label)
            BY <1>labels, <1>compiled, <1>source, SMT
                DEF \#(p)NativeLabeled, \#(p)SourceBranchAt, \#(p)SourceLabeled, \#(p)Labels,
                    \#(p)Receipts, \#(p)TerminalLabel, \#(p)AllSourceLabels
        <1>emitted.
            /\ \A label : \#(p)NativeLabeled(label) <=> \#(p)EmittedLabeled(label)
            /\ (Next <=> \#(p)NativeSteps)
            /\ (\#(p)NativeSteps <=> \#(p)SelectedSourceSteps)
            BY <1>dispatch, \#(p)ActualLabeledActionsAndNext, SMT DEF \#(p)NativeSteps, \#(p)SelectedSourceSteps
        <1>stutter. [\#(p)NativeSteps]_vars <=> [\#(p)SelectedSourceSteps]_vars
            BY <1>emitted, PTL
        <1>nativeStutter. [Next]_vars <=> [\#(p)NativeSteps]_vars
            BY <1>emitted, PTL
        <1>behavior. ([][Next]_vars) <=> ([][\#(p)NativeSteps]_vars)
            BY <1>nativeStutter, PTL
        <1>. QED BY <1>dispatch, <1>emitted, <1>stutter, <1>behavior,
            \#(p)CFG!NormalCFGIsTheSpecAndDeadlockSelection, PTL DEF \#(p)SelectedBehavior, Spec
        ====

        """#
        return (name, Data(proof.utf8))
    }
}
