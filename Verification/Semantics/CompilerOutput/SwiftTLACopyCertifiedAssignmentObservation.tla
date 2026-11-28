---- MODULE SwiftTLACopyCertifiedAssignmentObservation ----
EXTENDS SwiftTLACopyConfiguredBehavior

\* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3

LOCAL CopyAssignments == INSTANCE CertifiedReadAssignmentObservation
    WITH Keys <- SwiftTLACopyKeys, SwiftIntMin <- ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808),
         SwiftIntMax <- ((9 * 1000000000 + 223372036) * 1000000000 + 854775807)

CopyInputTyped == SwiftTLACopyBefore \in CopyAssignments!AssignmentBindings
LOCAL CopyRows(index) == SwiftTLACopyRows[index].copies
LOCAL CertifiedCopyAssignments(index) == CopyAssignments!ReadAssignmentRows(CopyRows(index))

LOCAL SelectedCopyHistory(index, history) ==
    LET rows == CertifiedCopyAssignments(index)
        count == Len(rows)
    IN /\ CopyAssignments!AssignmentListHistory(FALSE, SwiftTLACopyBefore, rows, history)
       /\ CopyAssignments!AssignmentListHistory(TRUE, SwiftTLACopyBefore, rows, history)
       /\ \A visit \in 0..count : CopyAssignments!AssignmentPrefixMeaning(SwiftTLACopyBefore, rows, history, visit)
       /\ history[count].failure = <<>>
       /\ SwiftTLACopyAfter = history[count].bindings

CertifiedCopyStep(label) ==
    \/ \E index \in DOMAIN SwiftTLACopyRows :
          /\ label = SwiftTLACopyRows[index].label
          /\ SwiftTLACopyControlBefore = SwiftTLACopyEntries[index]
          /\ SwiftTLACopyControlAfter = SwiftTLACopyDestinations[index]
          /\ \E history : SelectedCopyHistory(index, history)
    \/ /\ label = SwiftTLACopyTerminalLabel
       /\ SwiftTLACopySourceTermination

THEOREM ActualAuthoredCopyRowsAreTyped ==
    \A index \in DOMAIN SwiftTLACopyRows : CopyAssignments!TypedCopyRows(CopyRows(index))
    BY ONLY SwiftTLACopyActualFrontendSuppliesTheScheduledCopyRows, SMT
        DEF CopyAssignments!TypedCopyRows, CopyRows

THEOREM ActualSourceBranchUsesTheCertifiedCopyHistory ==
    ASSUME NEW index \in DOMAIN SwiftTLACopyRows, CopyInputTyped
    PROVE SwiftTLACopySourceBranch(index) <=>
                (/\ SwiftTLACopyControlBefore = SwiftTLACopyEntries[index]
                 /\ SwiftTLACopyControlAfter = SwiftTLACopyDestinations[index]
                 /\ \E history : SelectedCopyHistory(index, history))
    PROOF
    <1>. DEFINE copies == CopyRows(index)
                rows == CertifiedCopyAssignments(index)
    <1>shape. /\ CopyAssignments!TypedCopyRows(copies)
              /\ CopyAssignments!SupportedAssignmentList(rows)
              /\ Len(rows) = Len(copies)
        BY ActualAuthoredCopyRowsAreTyped, (index \in DOMAIN SwiftTLACopyRows),
           CopyAssignments!DirectReadsSupplySupportedIntegerAssignmentRows, SMT DEF copies, rows, CertifiedCopyAssignments
    <1>one. PICK history :
                /\ CopyAssignments!AssignmentListHistory(FALSE, SwiftTLACopyBefore, rows, history)
                /\ CopyAssignments!AssignmentListHistory(TRUE, SwiftTLACopyBefore, rows, history)
                /\ \A visit \in 0..Len(rows) :
                       CopyAssignments!AssignmentPrefixMeaning(SwiftTLACopyBefore, rows, history, visit)
        BY <1>shape, CopyInputTyped, CopyAssignments!CertifiedOrderedAssignmentListConstructsCompleteActionOutcome,
            SMT DEF CopyInputTyped
    <1>integers. CopyAssignments!IntegerDomain
        BY ONLY SMT DEF CopyAssignments!IntegerDomain
    <1>inputs.
        /\ SwiftTLACopyBefore \in CopyAssignments!AssignmentBindings
        /\ Len(rows) \in 0..Len(copies)
        BY ONLY CopyInputTyped, <1>shape, SMT DEF CopyInputTyped, CopyAssignments!TypedCopyRows
    <1>sourceBranch.
        CopyAssignments!SourceCopyBranch(SwiftTLACopyKeys, copies, SwiftTLACopyBefore, SwiftTLACopyAfter)
            <=> SwiftTLACopyRules!SourceCopyBranch(SwiftTLACopyKeys, copies, SwiftTLACopyBefore, SwiftTLACopyAfter)
        BY ONLY SMT DEF CopyAssignments!SourceCopyBranch, SwiftTLACopyRules!SourceCopyBranch,
            CopyAssignments!SourceCopyStateHistory, SwiftTLACopyRules!SourceCopyStateHistory,
            CopyAssignments!CopyReplace, SwiftTLACopyRules!CopyReplace
    <1>branch. \A history :
        CopyAssignments!AssignmentListHistory(FALSE, SwiftTLACopyBefore, rows, history) =>
           /\ history[Len(rows)].failure = <<>>
           /\ (SwiftTLACopyRules!SourceCopyBranch(SwiftTLACopyKeys, copies, SwiftTLACopyBefore, SwiftTLACopyAfter)
                 <=> SwiftTLACopyAfter = history[Len(rows)].bindings)
        <2>. SUFFICES ASSUME NEW seen, CopyAssignments!AssignmentListHistory(FALSE, SwiftTLACopyBefore, rows, seen)
                     PROVE /\ seen[Len(rows)].failure = <<>>
                           /\ (SwiftTLACopyRules!SourceCopyBranch(SwiftTLACopyKeys, copies, SwiftTLACopyBefore, SwiftTLACopyAfter)
                                 <=> SwiftTLACopyAfter = seen[Len(rows)].bindings)
            OBVIOUS
        <2>certified.
            /\ \A visit \in 0..Len(copies) : seen[visit].failure = <<>>
            /\ (CopyAssignments!SourceCopyBranch(SwiftTLACopyKeys, copies, SwiftTLACopyBefore, SwiftTLACopyAfter)
                  <=> SwiftTLACopyAfter = seen[Len(copies)].bindings)
            BY ONLY <1>shape, <1>inputs, <1>integers,
                CopyAssignments!AssignmentListHistory(FALSE, SwiftTLACopyBefore, rows, seen),
                CopyAssignments!CertifiedDirectReadsHaveExactlyTheSourceCopyBranch, SMT
                DEF rows, CertifiedCopyAssignments, copies
        <2>. QED BY ONLY <2>certified, <1>shape, <1>inputs, <1>sourceBranch, SMT
    <1>exists. SwiftTLACopyRules!SourceCopyBranch(SwiftTLACopyKeys, copies, SwiftTLACopyBefore, SwiftTLACopyAfter)
                 => (\E history : SelectedCopyHistory(index, history))
        PROOF
        <2>. SUFFICES ASSUME SwiftTLACopyRules!SourceCopyBranch(
                                    SwiftTLACopyKeys, copies, SwiftTLACopyBefore, SwiftTLACopyAfter)
                     PROVE \E history : SelectedCopyHistory(index, history)
            OBVIOUS
        <2>. WITNESS history
        <2>. QED BY <1>one, <1>branch, SMT DEF SelectedCopyHistory, rows
    <1>. QED BY <1>exists, <1>branch, SMT DEF SwiftTLACopySourceBranch,
        SwiftTLACopyControlBefore, SwiftTLACopyControlAfter, SwiftTLACopyRows, SwiftTLACopyKeys,
        SelectedCopyHistory, rows, copies, CopyRows

THEOREM ActualTLAAndNativeCopyStepsUseTheCertifiedAssignmentHistory ==
    ASSUME CopyInputTyped
    PROVE /\ \A label : SwiftTLACopyEmittedLabeled(label) <=> CertifiedCopyStep(label)
          /\ \A label : SwiftTLACopyNativeLabeled(label) <=> CertifiedCopyStep(label)
          /\ Next <=> (\E label : CertifiedCopyStep(label))
    PROOF
    <1>branch. \A index \in DOMAIN SwiftTLACopyRows : SwiftTLACopySourceBranch(index) <=>
                 (/\ SwiftTLACopyControlBefore = SwiftTLACopyEntries[index]
                  /\ SwiftTLACopyControlAfter = SwiftTLACopyDestinations[index]
                  /\ \E history : SelectedCopyHistory(index, history))
        BY ActualSourceBranchUsesTheCertifiedCopyHistory, SMT
    <1>source. \A label : SwiftTLACopySourceLabeled(label) <=> CertifiedCopyStep(label)
        BY <1>branch, SMT DEF SwiftTLACopySourceLabeled, CertifiedCopyStep, SwiftTLACopyRows, SwiftTLACopyTerminalLabel
    <1>. QED BY <1>source, SwiftTLACopyActualConfiguredCopyDispatchPreservesSteps, SwiftTLACopyActualLabeledActionsAndNext, SMT

====
