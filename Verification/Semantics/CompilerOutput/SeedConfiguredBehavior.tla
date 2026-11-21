---- MODULE SeedConfiguredBehavior ----
EXTENDS SwiftTLACopyConfiguredBehavior, SwiftTLASequentialControlProof

\* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
SourceSteps == SwiftTLACopySelectedSourceSteps
NativeSteps == SwiftTLACopyNativeSteps
SelectedBehavior == SwiftTLACopySelectedBehavior

THEOREM EmittedBehaviorStepMatchesSourceIncludingStuttering ==
    [Next]_vars <=> [SourceSteps]_vars
    PROOF
    <1>native. [Next]_vars <=> [NativeSteps]_vars
        BY SwiftTLACopyActualConfiguredCopyDispatchPreservesSteps, PTL DEF NativeSteps
    <1>. QED BY <1>native, SwiftTLACopyActualConfiguredCopyDispatchPreservesSteps, PTL
        DEF NativeSteps, SourceSteps

THEOREM NormalConfigurationUsesTheProvedStep ==
    SelectedBehavior <=> (Init /\ [][SourceSteps]_vars)
    PROOF
    <1>always. ([][NativeSteps]_vars) <=> ([][SourceSteps]_vars)
        BY SwiftTLACopyActualConfiguredCopyDispatchPreservesSteps, PTL DEF NativeSteps, SourceSteps
    <1>. QED BY <1>always, SwiftTLACopyActualConfiguredCopyDispatchPreservesSteps, PTL
        DEF NativeSteps, SelectedBehavior

THEOREM NormalConfigurationAndNativeDispatchPreserveSourceSteps ==
    /\ \A label : SwiftTLACopyNativeLabeled(label) <=> SwiftTLACopySourceLabeled(label)
    /\ ([NativeSteps]_vars <=> [SourceSteps]_vars)
    /\ (SelectedBehavior <=> (Init /\ [][NativeSteps]_vars))
    BY ONLY SwiftTLACopyActualConfiguredCopyDispatchPreservesSteps
        DEF NativeSteps, SourceSteps, SelectedBehavior

THEOREM NormalConfigurationUsesOnlyAuthoredSequentialControl ==
    /\ (SelectedBehavior => [][AuthoredSequentialStep]_vars)
    /\ NativeControlUsesAuthoredRoutes
PROOF
<1>step. Next => AuthoredSequentialStep
    BY ActualSequentialStepUsesAuthoredRoutes
<1>stuttering. [Next]_vars => [AuthoredSequentialStep]_vars
    BY <1>step, PTL
<1>. QED BY <1>stuttering, ActualSequentialStepUsesAuthoredRoutes, PTL
    DEF SelectedBehavior, SwiftTLACopySelectedBehavior, Spec
====
