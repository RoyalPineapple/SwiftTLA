--------------- MODULE ConditionalSelectionFailureProof ---------------
EXTENDS TLAPS, ConditionalSelectionFailure

SourceInit == pc = "select" /\ attempt \in BOOLEAN /\ selected = 0
Conditional(guard, yes, no) == IF guard THEN yes ELSE no
GuardedBranches(guard, yes, no) == (guard /\ yes) \/ (~guard /\ no)

THEOREM ConditionalLoweringLaw ==
    ASSUME NEW guard \in BOOLEAN, NEW yes \in BOOLEAN, NEW no \in BOOLEAN
    PROVE Conditional(guard, yes, no) <=> GuardedBranches(guard, yes, no)
    BY SMT DEF Conditional, GuardedBranches

MatchingChoice == \E member \in {1} : FALSE
TrueBranch ==
    MatchingChoice /\ pc' = "Done" /\ selected' = 1 /\ UNCHANGED attempt
FalseBranch ==
    pc' = "Done" /\ selected' = 2 /\ UNCHANGED attempt
SourceSelect ==
    /\ pc = "select"
    /\ Conditional(attempt, TrueBranch, FalseBranch)
CompiledSelect ==
    pc = "select" /\ GuardedBranches(attempt, TrueBranch, FalseBranch)
SourceTerminating ==
    pc = "Done" /\ UNCHANGED <<pc, attempt, selected>>
SourceNext == SourceSelect \/ SourceTerminating
SourceFailure == pc = "select" /\ Conditional(attempt, ~MatchingChoice, FALSE)
CompiledFailure ==
    pc = "select" /\ GuardedBranches(attempt, ~MatchingChoice, FALSE)
SourceLabeled(label) ==
    \/ label = "select" /\ SourceSelect
    \/ label = "Terminating" /\ SourceTerminating
EmittedLabeled(label) ==
    \/ label = "select" /\ select
    \/ label = "Terminating" /\ Terminating

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM ConditionalChoiceLoweringPreservesStepAndFailure ==
    ASSUME attempt \in BOOLEAN
    PROVE /\ (SourceSelect <=> CompiledSelect)
          /\ (SourceFailure <=> CompiledFailure)
    BY ConditionalLoweringLaw, SMT
        DEF SourceSelect, CompiledSelect, SourceFailure,
            CompiledFailure, Conditional, GuardedBranches

THEOREM SelectedBranchPreservesCompleteStep ==
    ASSUME attempt \in BOOLEAN
    PROVE select <=> SourceSelect
    BY ConditionalChoiceLoweringPreservesStepAndFailure, SMT
        DEF select, CompiledSelect, TrueBranch, FalseBranch,
            MatchingChoice, GuardedBranches

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
    ASSUME attempt \in BOOLEAN
    PROVE /\ (__SwiftTLAChoiceFailure0 <=> SourceFailure)
          /\ (__SwiftTLAEvaluationOK <=> ~SourceFailure)
    BY ConditionalChoiceLoweringPreservesStepAndFailure, SMT
        DEF __SwiftTLAChoiceFailure0, __SwiftTLAEvaluationOK,
            CompiledFailure, MatchingChoice, GuardedBranches

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
            Conditional, TrueBranch, FalseBranch, MatchingChoice,
            __SwiftTLAChoiceFailure0

WrongBranchFailure == pc = "select" /\ attempt = FALSE

THEOREM ReversedBranchFailureIsRejected ==
    ASSUME pc = "select", attempt = TRUE
    PROVE __SwiftTLAChoiceFailure0 /\ ~WrongBranchFailure
    BY SMT DEF __SwiftTLAChoiceFailure0, WrongBranchFailure

======================================================================
