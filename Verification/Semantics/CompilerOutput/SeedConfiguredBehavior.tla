---- MODULE SeedConfiguredBehavior ----
EXTENDS SwiftTLANativeActionProof, SwiftTLASequentialControlProof, NormalSeedCFG

\* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
SourceSteps == SourceStay(Before, After) \/ SourceTerminating(Before, After)
SelectedBehavior == (ActualCFG = SeedCFG) /\ Spec

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

THEOREM NormalConfigurationUsesOnlyAuthoredSequentialControl ==
    /\ (SelectedBehavior => [][AuthoredSequentialStep]_vars)
    /\ NativeControlUsesAuthoredRoutes
PROOF
<1>step. Next => AuthoredSequentialStep
    BY ActualSequentialStepUsesAuthoredRoutes
<1>stuttering. [Next]_vars => [AuthoredSequentialStep]_vars
    BY <1>step, PTL
<1>. QED BY <1>stuttering, ActualSequentialStepUsesAuthoredRoutes, PTL
    DEF SelectedBehavior, Spec
====
