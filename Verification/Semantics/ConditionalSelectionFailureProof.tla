--------------- MODULE ConditionalSelectionFailureProof ---------------
EXTENDS TLAPS, ConditionalSelectionFailure

SourceInit == pc = "select" /\ attempt \in BOOLEAN /\ selected = 0
SourceSelect ==
    /\ pc = "select"
    /\ attempt = FALSE
    /\ pc' = "Done"
    /\ selected' = 2
    /\ UNCHANGED attempt
SourceTerminating ==
    pc = "Done" /\ UNCHANGED <<pc, attempt, selected>>
SourceNext == SourceSelect \/ SourceTerminating
SourceFailure == pc = "select" /\ attempt = TRUE
SourceLabeled(label) ==
    \/ label = "select" /\ SourceSelect
    \/ label = "Terminating" /\ SourceTerminating
EmittedLabeled(label) ==
    \/ label = "select" /\ select
    \/ label = "Terminating" /\ Terminating

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM SelectedBranchPreservesCompleteStep ==
    ASSUME attempt \in BOOLEAN
    PROVE select <=> SourceSelect
    BY SMT DEF select, SourceSelect

THEOREM InternalTerminatingStepAgrees ==
    Terminating <=> SourceTerminating
    BY SMT DEF Terminating, SourceTerminating

THEOREM CompleteLabeledRelationAgrees ==
    ASSUME NEW label, attempt \in BOOLEAN
    PROVE /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY SelectedBranchPreservesCompleteStep,
        InternalTerminatingStepAgrees, SMT
        DEF Next, SourceNext, EmittedLabeled, SourceLabeled

THEOREM SelectedFailureAndCheckingInvariantAgree ==
    /\ (__SwiftTLAChoiceFailure0 <=> SourceFailure)
    /\ (__SwiftTLAEvaluationOK <=> ~SourceFailure)
    BY SMT DEF __SwiftTLAChoiceFailure0, __SwiftTLAEvaluationOK,
        SourceFailure

THEOREM BranchVerdictsAgree ==
    ASSUME pc = "select", attempt \in BOOLEAN
    PROVE /\ (attempt = TRUE =>
                __SwiftTLAChoiceFailure0 /\ ~ENABLED Next)
          /\ (attempt = FALSE =>
                ~__SwiftTLAChoiceFailure0 /\ ENABLED Next)
    BY SelectedBranchPreservesCompleteStep,
        InternalTerminatingStepAgrees,
        SelectedFailureAndCheckingInvariantAgree,
        ExpandENABLED, SMT
        DEF Next, select, Terminating,
            SourceSelect, SourceTerminating, SourceFailure,
            __SwiftTLAChoiceFailure0

WrongBranchFailure == pc = "select" /\ attempt = FALSE

THEOREM ReversedBranchFailureIsRejected ==
    ASSUME pc = "select", attempt = TRUE
    PROVE __SwiftTLAChoiceFailure0 /\ ~WrongBranchFailure
    BY SMT DEF __SwiftTLAChoiceFailure0, WrongBranchFailure

======================================================================
