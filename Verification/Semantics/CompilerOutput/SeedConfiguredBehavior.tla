---- MODULE SeedConfiguredBehavior ----
EXTENDS SwiftTLANativeActionProof, CompilerInputPageBlock1

\* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
\* The seed's normal TLC configuration selects Spec and requests deadlock checking.
SeedCFG == <<83, 80, 69, 67, 73, 70, 73, 67, 65, 84, 73, 79, 78, 32, 83, 112, 101, 99, 10, 67, 72, 69, 67, 75, 95, 68, 69, 65, 68, 76, 79, 67, 75, 32, 84, 82, 85, 69, 10>>
ActualCFG == [i \in 1..CompilerInputSize |-> CompilerInputByte[i - 1]]

SourceSteps == SourceStay(Before, After) \/ SourceTerminating(Before, After)
SelectedBehavior == (ActualCFG = SeedCFG) /\ Spec

THEOREM NormalCFGIsTheSpecAndDeadlockSelection ==
    ActualCFG = SeedCFG
    PROOF
    <1>len. DOMAIN ActualCFG = DOMAIN SeedCFG BY SMT DEF ActualCFG, SeedCFG, CompilerInputSize
    <1>bytes. \A i \in DOMAIN SeedCFG : ActualCFG[i] = SeedCFG[i]
        BY ONLY CompilerInputPageBlock1AtFileOffsets, SMT DEF ActualCFG, SeedCFG, CompilerInputSize
    <1>. QED BY <1>len, <1>bytes, SMT DEF ActualCFG, SeedCFG

THEOREM EmittedBehaviorStepMatchesSourceIncludingStuttering ==
    [Next]_vars <=> [SourceSteps]_<<pc, first, second, last>>
    PROOF
    <1>step. Next <=> SourceSteps
        BY ActualNextComposesTheCompleteLabeledActions, SMT DEF SourceSteps
    <1>. QED BY <1>step, PTL DEF vars

THEOREM NormalConfigurationUsesTheProvedStep ==
    SelectedBehavior <=> (Init /\ [][SourceSteps]_<<pc, first, second, last>>)
    PROOF
    <1>always. ([][Next]_vars) <=> ([][SourceSteps]_<<pc, first, second, last>>)
        BY EmittedBehaviorStepMatchesSourceIncludingStuttering, PTL
    <1>. QED BY NormalCFGIsTheSpecAndDeadlockSelection, <1>always, PTL
        DEF SelectedBehavior, Spec, vars

NativeSteps == \E label : NativeLabeled(label, Before, After)

THEOREM NormalConfigurationAndNativeDispatchPreserveSourceSteps ==
    /\ \A label : NativeLabeled(label, Before, After) <=> SourceLabeled(label, Before, After)
    /\ ([NativeSteps]_vars <=> [SourceSteps]_vars)
    /\ (SelectedBehavior <=> (Init /\ [][NativeSteps]_vars))
    PROOF
    <1>label. \A label : NativeLabeled(label, Before, After) <=> SourceLabeled(label, Before, After)
        BY ONLY NativeActionObservationsMatchActualNext, ActualNextComposesTheCompleteLabeledActions, SMT
    <1>steps. NativeSteps <=> Next
        BY ONLY NativeActionObservationsMatchActualNext DEF NativeSteps
    <1>stutter. [NativeSteps]_vars <=> [SourceSteps]_vars
        BY <1>steps, EmittedBehaviorStepMatchesSourceIncludingStuttering, PTL DEF vars
    <1>behaviors. ([][NativeSteps]_vars) <=> ([][SourceSteps]_vars)
        BY <1>stutter, PTL
    <1>. QED BY <1>label, <1>stutter, <1>behaviors, NormalConfigurationUsesTheProvedStep, PTL DEF vars
====
