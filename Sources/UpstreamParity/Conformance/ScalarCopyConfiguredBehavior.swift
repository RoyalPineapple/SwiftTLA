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
        } + ["[reads |-> <<>>, writes |-> \(p)NativeRules!CopyEntryRoutes(\(p)Keys), "
            + "entry |-> \(p)TerminalControl, control |-> <<\"state\", \(p)NativeRules!NativeCopyControlSlot>>]"]
        let labels = TLAValue.tuple(layout.actions.map { .string($0.renderedName) })
        let compiled = actions.indices.map { "\(p)CompiledBranch\($0 + 1)" }.joined(separator: ", ")
        let readDefinitions = actions.indices.map { "\(p)Reads\($0 + 1)" }.joined(separator: ", ")
        let writeDefinitions = actions.indices.map { "\(p)Writes\($0 + 1)" }.joined(separator: ", ")
        let routeTheorems = actions.indices.map { "\(p)Row\($0 + 1)" }.joined(separator: ", ")
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(parentName), CompilerInputPageBlock1, SequenceTheorems_proofs
        LOCAL \#(p)CFG == INSTANCE NormalSeedCFG
        LOCAL \#(p)NativeRules == INSTANCE NativeScalarCopyRule
            WITH Vars <- {}, Values <- {}, ActionLabels <- {}, FailureValues <- {}, NoFailure <- <<>>
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
                DEF \#(p)NativeRows, \#(p)Native!NativeActionRows, \#(p)Native!NativeActionDispatchLabels, \#(p)Labels,
                    \#(p)TerminalLabel, \#(p)Receipts, \#(p)RenderedLabels, \#(p)AllSourceLabels
        <1>known. \A index \in DOMAIN \#(p)NativeRows :
            \#(p)NativeRules!NativeCopyKnownRoles(\#(p)NativeRows[index][2], \#(p)Keys,
                \#(p)FormalNames, \#(p)ControlKey)
            BY ONLY \#(p)ActualLayoutKeys, SMT
                DEF \#(p)NativeRules!NativeCopyKnownRoles, \#(p)NativeRules!NativeCopyPhysicalKeys,
                    \#(p)NativeRows, \#(p)Native!NativeActionRows, \#(p)FormalNames, \#(p)ControlKey
        <1>inverse.
            /\ \A key \in \#(p)Keys :
                \#(p)NativeRules!NativeCopyKey(\#(p)Keys, \#(p)FormalNames, \#(p)ControlKey,
                    \#(p)FormalNames[key]) = key
            /\ \#(p)NativeRules!NativeCopyKey(\#(p)Keys, \#(p)FormalNames, \#(p)ControlKey,
                    \#(p)ControlKey) = \#(p)NativeRules!NativeCopyControlSlot
            BY ONLY \#(p)ActualLayoutKeys, SMT
                DEF \#(p)NativeRules!NativeCopyKey, \#(p)FormalNames, \#(p)ControlKey
        <1>plans. \A index \in DOMAIN \#(p)NativeRows :
            LET receipt == \#(p)Receipts[index] IN
                \#(p)NativeRules!NativeCompleteCopyPlan(\#(p)NativePlan(index), \#(p)Keys,
                   receipt.reads, receipt.writes, receipt.entry, receipt.control)
            PROOF
            <2>. SUFFICES ASSUME NEW index \in DOMAIN \#(p)NativeRows
                         PROVE LET receipt == \#(p)Receipts[index] IN
                            \#(p)NativeRules!NativeCompleteCopyPlan(\#(p)NativePlan(index), \#(p)Keys,
                               receipt.reads, receipt.writes, receipt.entry, receipt.control)
                OBVIOUS
            <2>. DEFINE plan == \#(p)NativePlan(index)
                        receipt == \#(p)Receipts[index]
                        fields == \#(p)NativeRules!NativeCopyFields(\#(p)Keys)
                        raw == \#(p)NativeRows[index][2]
                        decoded(key) == \#(p)NativeRules!NativeCopyKey(
                            \#(p)Keys, \#(p)FormalNames, \#(p)ControlKey, key)
                        decode(value) == IF value[1] = "state" THEN <<"state", decoded(value[2])>> ELSE value
                        encode(value) == IF value[1] = "state" THEN <<"state",
                            IF value[2] = \#(p)NativeRules!NativeCopyControlSlot
                            THEN \#(p)ControlKey ELSE \#(p)FormalNames[value[2]]>>
                            ELSE value
            <2>input.
                /\ plan.guards = <<receipt.entry>>
                /\ plan.captures = receipt.reads
                /\ \A position \in DOMAIN receipt.reads :
                    /\ receipt.reads[position][1] \in {"state", "capture", "literal"}
                    /\ receipt.reads[position][1] = "state" => receipt.reads[position][2] \in \#(p)Keys
                BY ONLY (index \in DOMAIN \#(p)NativeRows), <1>inverse, \#(p)ActualLayoutKeys, SMT
                    DEF plan, receipt, \#(p)NativePlan, \#(p)NativeRules!NativeCopyRekey,
                        \#(p)NativeRows, \#(p)Native!NativeActionRows, \#(p)Receipts,
                        \#(readDefinitions), \#(p)Entries, \#(p)TerminalControl, \#(p)FormalNames,
                    \#(p)ControlKey
            <2>known. \#(p)NativeRules!NativeCopyKnownRoles(raw, \#(p)Keys, \#(p)FormalNames, \#(p)ControlKey)
                BY ONLY (index \in DOMAIN \#(p)NativeRows), <1>known, SMT DEF raw
            <2>domain. /\ Len(raw.writes) \in Nat
                       /\ DOMAIN raw.writes = 1..Len(raw.writes)
                BY ONLY (index \in DOMAIN \#(p)NativeRows), SMT
                    DEF raw, \#(p)NativeRows, \#(p)Native!NativeActionRows
            <2>rekey.
                /\ DOMAIN plan.writes = DOMAIN raw.writes
                /\ \A position \in DOMAIN raw.writes :
                     plan.writes[position] = <<decoded(raw.writes[position][1]), decode(raw.writes[position][2])>>
                BY ONLY SMT DEF plan, raw, \#(p)NativePlan, \#(p)NativeRules!NativeCopyRekey, decoded, decode
            <2>. DEFINE values == {plan.writes[position] : position \in DOMAIN raw.writes}
            <2>typed. plan.writes \in [1..Len(raw.writes) -> values]
                BY ONLY <2>domain, <2>rekey, SMT
                    DEF values, plan, raw, \#(p)NativePlan, \#(p)NativeRules!NativeCopyRekey
            <2>seq. plan.writes \in Seq(values)
                BY ONLY <2>domain, <2>typed, SeqDef, SMT
            <2>size. /\ Len(plan.writes) \in Nat
                      /\ DOMAIN plan.writes = 1..Len(plan.writes)
                BY ONLY <2>seq, LenProperties, SMT
            <2>rawFields. \A key \in \#(p)NativeRules!NativeCopyPhysicalKeys(
                  \#(p)Keys, \#(p)FormalNames, \#(p)ControlKey) :
                \E position \in DOMAIN raw.writes : raw.writes[position][1] = key
                BY ONLY (index \in DOMAIN \#(p)NativeRows), \#(p)ActualLayoutKeys, SMT
                    DEF raw, \#(p)NativeRows, \#(p)Native!NativeActionRows,
                        \#(p)NativeRules!NativeCopyPhysicalKeys, \#(p)FormalNames, \#(p)ControlKey
            <2>coverage.
                /\ Len(plan.writes) \in Nat
                /\ DOMAIN plan.writes = 1..Len(plan.writes)
                /\ \A position \in DOMAIN plan.writes : plan.writes[position][1] \in fields
                /\ \A key \in fields : \E position \in DOMAIN plan.writes : plan.writes[position][1] = key
                BY ONLY <2>size, <2>rekey, <2>rawFields, <2>known, <1>inverse, SMT
                    DEF fields, decoded, \#(p)NativeRules!NativeCopyFields,
                        \#(p)NativeRules!NativeCopyKnownRoles, \#(p)NativeRules!NativeCopyPhysicalKeys
            <2>keys. /\ \#(p)Keys \subseteq STRING
                     /\ \#(p)NativeRules!NativeCopyControlSlot \notin \#(p)Keys
                BY ONLY \#(p)ActualLayoutKeys, SMT DEF \#(p)NativeRules!NativeCopyControlSlot
            <2>refs. \A key \in \#(p)Keys :
                     /\ receipt.writes[key][1] = "state" =>
                            /\ receipt.writes[key] = <<"state", receipt.writes[key][2]>>
                            /\ receipt.writes[key][2] \in \#(p)Keys
                     /\ receipt.writes[key][1] \in {"state", "capture", "literal"}
                BY ONLY (index \in DOMAIN \#(p)NativeRows), \#(p)ActualLayoutKeys, SMT
                    DEF receipt, \#(p)Receipts, \#(p)NativeRows, \#(p)Native!NativeActionRows,
                        \#(writeDefinitions), \#(p)Source!WitnessCopyFields, \#(p)NativeRules!CopyEntryRoutes
            <2>control. receipt.control[1] = "control" \/
                    receipt.control = <<"state", \#(p)NativeRules!NativeCopyControlSlot>>
                BY ONLY (index \in DOMAIN \#(p)NativeRows), SMT
                    DEF receipt, \#(p)Receipts, \#(p)NativeRows, \#(p)Native!NativeActionRows
            <2>roles.
                /\ \#(p)Keys \subseteq STRING
                /\ \#(p)NativeRules!NativeCopyControlSlot \notin \#(p)Keys
                /\ \A key \in \#(p)Keys : receipt.writes[key][1] = "state" => receipt.writes[key][2] \in \#(p)Keys
                /\ \A key \in \#(p)Keys : receipt.writes[key][1] \in {"state", "capture", "literal"}
                /\ (receipt.control[1] = "control" \/ receipt.control = <<"state", \#(p)NativeRules!NativeCopyControlSlot>>)
                BY ONLY <2>keys, <2>refs, <2>control, SMT
            <2>roundtrip. \A value :
                (value[1] = "state" => /\ value = <<"state", value[2]>>
                                         /\ value[2] \in fields) => decode(encode(value)) = value
                BY ONLY <1>inverse, SMT DEF decode, encode, decoded, fields, \#(p)NativeRules!NativeCopyFields
            <2>rawValues. \A position \in DOMAIN raw.writes :
                LET write == raw.writes[position] IN
                    \/ /\ write[1] = \#(p)ControlKey
                       /\ write[2] = encode(receipt.control)
                    \/ \E key \in \#(p)Keys :
                         /\ write[1] = \#(p)FormalNames[key]
                         /\ write[2] = encode(receipt.writes[key])
                PROOF
                <3>. TAKE position \in DOMAIN raw.writes
                <3>. DEFINE write == raw.writes[position]
                            matches == \/ /\ write[1] = \#(p)ControlKey
                                            /\ write[2] = encode(receipt.control)
                                       \/ \E key \in \#(p)Keys :
                                            /\ write[1] = \#(p)FormalNames[key]
                                            /\ write[2] = encode(receipt.writes[key])
                <3>copy. index \in DOMAIN \#(p)Labels => matches
                    BY ONLY (index \in DOMAIN \#(p)NativeRows), (position \in DOMAIN raw.writes),
                        \#(p)ActualLayoutKeys, SMT
                        DEF matches, write, raw, receipt, encode, \#(p)Receipts, \#(p)NativeRows,
                            \#(p)Native!NativeActionRows, \#(writeDefinitions), \#(p)Source!WitnessCopyFields,
                            \#(p)Destinations, \#(p)FormalNames, \#(p)ControlKey,
                            \#(p)NativeRules!NativeCopyControlSlot, \#(p)Labels
                <3>done. index \notin DOMAIN \#(p)Labels => matches
                    BY ONLY (index \in DOMAIN \#(p)NativeRows), (position \in DOMAIN raw.writes),
                        \#(p)ActualLayoutKeys, SMT
                        DEF matches, write, raw, receipt, encode, \#(p)Receipts, \#(p)NativeRows,
                            \#(p)Native!NativeActionRows, \#(p)NativeRules!CopyEntryRoutes,
                            \#(p)FormalNames, \#(p)ControlKey,
                            \#(p)NativeRules!NativeCopyControlSlot, \#(p)Labels
                <3>. QED BY ONLY <3>copy, <3>done, SMT DEF matches, write
            <2>payload. \A position \in DOMAIN plan.writes :
                    LET key == plan.writes[position][1]
                    IN plan.writes[position][2] = (IF key = \#(p)NativeRules!NativeCopyControlSlot
                                                   THEN receipt.control ELSE receipt.writes[key])
                BY ONLY <2>rekey, <2>rawValues, <2>roundtrip, <2>roles, <2>refs, <1>inverse, SMT
                    DEF decoded, fields, \#(p)NativeRules!NativeCopyFields
            <2>. QED BY ONLY <2>input, <2>coverage, <2>payload, <2>roles, SMT
                DEF plan, receipt, fields, \#(p)NativeRules!NativeCompleteCopyPlan
        <1>physical. \A index \in DOMAIN \#(p)NativeRows :
            LET receipt == \#(p)Receipts[index] IN
                \#(p)NativeBranch(index) <=>
                    /\ \#(p)ControlBefore = receipt.entry
                    /\ \#(p)ControlAfter = (IF receipt.control[1] = "control"
                                               THEN receipt.control[2] ELSE \#(p)ControlBefore)
                    /\ \#(p)NativeRules!CompiledCopyBranch(\#(p)Keys, \#(p)Before, receipt.reads, receipt.writes, \#(p)After)
            PROOF
            <2>. TAKE index \in DOMAIN \#(p)NativeRows
            <2>. DEFINE receipt == \#(p)Receipts[index]
            <2>plan. \#(p)NativeRules!NativeCompleteCopyPlan(\#(p)NativePlan(index), \#(p)Keys,
                receipt.reads, receipt.writes, receipt.entry, receipt.control)
                BY ONLY <1>plans, (index \in DOMAIN \#(p)NativeRows), SMT DEF receipt
            <2>. QED BY ONLY <2>plan, \#(p)ActualLayoutKeys,
                \#(p)NativeRules!ValidatedNativeCopyPlansHaveTheCompleteCompiledObservation, SMT
                DEF \#(p)NativeBranch
        <1>terminal. \#(p)NativeRules!CompiledCopyBranch(\#(p)Keys, \#(p)Before,
            <<>>, \#(p)NativeRules!CopyEntryRoutes(\#(p)Keys), \#(p)After) <=> \#(p)Before = \#(p)After
            BY ONLY \#(p)ActualLayoutKeys, \#(p)NativeRules!EmptyCopyPlanRetainsTheCompleteState, SMT
        <1>copyRule. \A reads, writes :
            \#(p)NativeRules!CompiledCopyBranch(\#(p)Keys, \#(p)Before, reads, writes, \#(p)After)
            <=> \#(p)Rules!CompiledCopyBranch(\#(p)Keys, \#(p)Before, reads, writes, \#(p)After)
            BY ONLY SMT DEF \#(p)NativeRules!CompiledCopyBranch, \#(p)Rules!CompiledCopyBranch,
                \#(p)NativeRules!CopyCaptureHistory, \#(p)Rules!CopyCaptureHistory,
                \#(p)NativeRules!CopyMaterializedState, \#(p)Rules!CopyMaterializedState,
                \#(p)NativeRules!CopyReferenceValue, \#(p)Rules!CopyReferenceValue
        <1>compiled. \A index \in DOMAIN \#(p)NativeRows :
             \#(p)NativeBranch(index) <=> \#(p)CompiledBranches[index]
            BY ONLY <1>labels, <1>physical, <1>terminal, <1>copyRule, SMT
                DEF \#(p)Receipts, \#(p)CompiledBranches, \#(p)SourceTermination,
                    \#(p)NativeRules!NativeCopyControlSlot, \#(p)ControlBefore, \#(p)ControlAfter, \#(p)TerminalControl,
                    \#(compiled)
        <1>source. \A index \in DOMAIN \#(p)NativeRows :
            \#(p)CompiledBranches[index] <=> \#(p)SourceBranchAt(index)
            BY <1>labels, \#(routeTheorems), SMT
                DEF \#(p)CompiledBranches, \#(p)SourceBranchAt, \#(p)Labels, \#(p)Receipts
        <1>dispatch. \A label : \#(p)NativeLabeled(label) <=> \#(p)SourceLabeled(label)
            BY ONLY <1>labels, <1>compiled, <1>source, SMT
                DEF \#(p)NativeLabeled, \#(p)SourceBranchAt, \#(p)SourceLabeled, \#(p)Labels, \#(p)Rows,
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
        <1>configuration. \#(p)CFG!ActualCFG = \#(p)CFG!SeedCFG
            BY ONLY \#(p)CFG!NormalCFGIsTheSpecAndDeadlockSelection,
                CompilerInputPageBlock1AtFileOffsets, CompilerInputDomain, SMT
                DEF CompilerInputSize, \#(p)CFG!CompilerInputSize
        <1>selected. \#(p)SelectedBehavior <=> (Init /\ [][\#(p)NativeSteps]_vars)
            BY ONLY <1>configuration, <1>behavior, PTL DEF \#(p)SelectedBehavior, Spec, vars
        <1>. QED BY ONLY <1>configuration, <1>dispatch, <1>emitted, <1>stutter, <1>selected
        ====

        """#
        return (name, Data(proof.utf8))
    }
}
