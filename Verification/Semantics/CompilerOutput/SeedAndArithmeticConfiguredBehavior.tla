---- MODULE SeedAndArithmeticConfiguredBehavior ----
EXTENDS SeedConfiguredBehavior, SwiftTLACopyCertifiedAssignmentObservation, CallerInputPageBlock1

VARIABLES arithmeticPC, arithmeticCount

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
    BY ONLY Arithmetic!NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking
<1>overflow. ASSUME Arithmetic!Init
    PROVE /\ Arithmetic!RHSOutputSelectedSubExpressions = {<<2, 3>>}
          /\ Arithmetic!RHSOutputActualFailures = {Arithmetic!ActualNativeProjection}
          /\ Arithmetic!RHSOutputActualFailures =
            {[site |-> 2, target |-> "count",
              payload |-> <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>,
              completed |-> <<Arithmetic!RHSOutputMax>>, before |-> [count |-> Arithmetic!RHSOutputMax]]}
          /\ ~ENABLED Arithmetic!Next
          /\ ~Arithmetic!RHSOutputSelectedEvaluationCheck
    BY Arithmetic!Init, Arithmetic!ActualInitialEventRecordsTheExactOverflowAndPrecedingBindings, SMT
<1>. QED BY ONLY <1>copy, <1>certified, <1>cfg, <1>overflow, PTL

====
