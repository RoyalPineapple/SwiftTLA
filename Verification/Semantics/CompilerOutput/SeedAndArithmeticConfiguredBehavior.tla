---- MODULE SeedAndArithmeticConfiguredBehavior ----
EXTENDS SeedConfiguredBehavior, SwiftTLACopyCertifiedAssignmentObservation, CallerInputPageBlock1,
        OrderedOverflowInitialDisabled

\* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
\* CallerInputPage1 CallerInputPage2 CallerInputPage3 CallerInputPage4 CallerInputPage5

LOCAL Arithmetic == INSTANCE SwiftTLAOrderedRHSBackendAgreement
    WITH pc <- arithmeticPC, count <- arithmeticCount

THEOREM ConfiguredNativeAndTLAUseTheCertifiedCopyAndOverflowOutcomes ==
    /\ (\A label : SwiftTLACopyNativeLabeled(label) <=> SwiftTLACopySourceLabeled(label))
    /\ ([NativeSteps]_vars <=> [SourceSteps]_vars)
    /\ (SelectedBehavior <=> (Init /\ [][NativeSteps]_vars))
    /\ (CopyInputTyped =>
        /\ \A label : SwiftTLACopyEmittedLabeled(label) <=> CertifiedCopyStep(label)
        /\ \A label : SwiftTLACopyNativeLabeled(label) <=> CertifiedCopyStep(label)
        /\ Next <=> (\E label : CertifiedCopyStep(label)))
    /\ Arithmetic!LocalOrderedRHSActualCFG = Arithmetic!LocalOrderedRHSExpectedCFG
    /\ (Arithmetic!Init =>
        /\ Arithmetic!RHSOutputSelectedSubExpressions = {<<2, 3>>}
        /\ Arithmetic!RHSOutputActualFailures = {Arithmetic!ActualNativeProjection}
        /\ Arithmetic!RHSOutputActualFailures =
            {[site |-> 2, target |-> "count",
              payload |-> <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>,
              completed |-> <<Arithmetic!RHSOutputMax>>, before |-> [count |-> Arithmetic!RHSOutputMax]]}
        /\ ~ENABLED Arithmetic!Next
        /\ ~Arithmetic!RHSOutputSelectedEvaluationCheck)
PROOF
<1>copy. /\ (\A label : SwiftTLACopyNativeLabeled(label) <=> SwiftTLACopySourceLabeled(label))
         /\ ([NativeSteps]_vars <=> [SourceSteps]_vars)
         /\ (SelectedBehavior <=> (Init /\ [][NativeSteps]_vars))
    BY ONLY NormalConfigurationAndNativeDispatchPreserveSourceSteps
<1>certified. ASSUME CopyInputTyped
              PROVE /\ \A label : SwiftTLACopyEmittedLabeled(label) <=> CertifiedCopyStep(label)
                    /\ \A label : SwiftTLACopyNativeLabeled(label) <=> CertifiedCopyStep(label)
                    /\ Next <=> (\E label : CertifiedCopyStep(label))
    BY CopyInputTyped, ActualTLAAndNativeCopyStepsUseTheCertifiedAssignmentHistory
<1>cfg. Arithmetic!LocalOrderedRHSActualCFG = Arithmetic!LocalOrderedRHSExpectedCFG
    BY ONLY CallerInputDomain, CallerInputPageBlock1AtFileOffsets,
        Arithmetic!NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking, SMT
        DEF CallerInputSize, Arithmetic!CallerInputSize
<1>overflow. ASSUME Arithmetic!Init
    PROVE /\ Arithmetic!RHSOutputSelectedSubExpressions = {<<2, 3>>}
          /\ Arithmetic!RHSOutputActualFailures = {Arithmetic!ActualNativeProjection}
          /\ Arithmetic!RHSOutputActualFailures =
            {[site |-> 2, target |-> "count",
              payload |-> <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>,
              completed |-> <<Arithmetic!RHSOutputMax>>, before |-> [count |-> Arithmetic!RHSOutputMax]]}
          /\ ~Arithmetic!RHSOutputSelectedEvaluationCheck
    BY ONLY Arithmetic!Init, CallerInputDomain, CallerInputPageBlock1AtFileOffsets,
        Arithmetic!ActualInitialEventRecordsTheExactOverflowAndPrecedingBindings, PTL
        DEF CallerInputSize, Arithmetic!CallerInputSize
<1>blocked. ASSUME Arithmetic!Init
             PROVE ~ENABLED Arithmetic!Next
    <2>entry. OverflowActions!Init
        BY ONLY Arithmetic!Init, SMT DEF Arithmetic!Init, OverflowActions!Init
    <2>disabled. ~ENABLED OverflowActions!Next
        BY ONLY <2>entry, InitialOrderedOverflowHasNoSuccessor, PTL
    <2>. QED BY ONLY <2>disabled, PTL
        DEF Arithmetic!Next, Arithmetic!advance, Arithmetic!Terminating,
            OverflowActions!Next, OverflowActions!advance, OverflowActions!Terminating
<1>. QED BY ONLY <1>copy, <1>certified, <1>cfg, <1>overflow, <1>blocked, PTL

====
