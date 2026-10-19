--------------- MODULE ConditionalSelectionFailureProof ---------------
EXTENDS TLAPS, ConditionalSelectionFailure, ConditionalOutcomeRules

SourceInit == pc = "select" /\ attempt \in BOOLEAN /\ selected = 0

MatchingChoice == \E member \in {1} : FALSE
TrueBranch ==
    MatchingChoice /\ pc' = "Done" /\ selected' = 1 /\ UNCHANGED attempt
FalseBranch ==
    pc' = "Done" /\ selected' = 2 /\ UNCHANGED attempt
SourceSelect ==
    /\ pc = "select"
    /\ DefinedConditional(TRUE, attempt, TrueBranch, FalseBranch)
CompiledSelect ==
    pc = "select" /\ DefinedGuardedBranches(TRUE, attempt, TrueBranch, FalseBranch)
SourceTerminating ==
    pc = "Done" /\ UNCHANGED <<pc, attempt, selected>>
SourceNext == SourceSelect \/ SourceTerminating
SourceFailure == pc = "select" /\ DefinedConditional(TRUE, attempt, ~MatchingChoice, FALSE)
CompiledFailure ==
    pc = "select" /\ DefinedGuardedBranches(TRUE, attempt, ~MatchingChoice, FALSE)
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
    BY DefinedConditionalPreservesStepAndFirstFailure, SMT
        DEF SourceSelect, CompiledSelect, SourceFailure,
            CompiledFailure, DefinedConditional, DefinedGuardedBranches

THEOREM SelectedBranchPreservesCompleteStep ==
    ASSUME attempt \in BOOLEAN
    PROVE select <=> SourceSelect
    BY ConditionalChoiceLoweringPreservesStepAndFailure, SMT
        DEF select, CompiledSelect, TrueBranch, FalseBranch,
            MatchingChoice, DefinedGuardedBranches

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
          /\ (__SwiftTLAAnyEvaluationFailure0 <=> SourceFailure)
          /\ (__SwiftTLAEvaluationOK <=> ~SourceFailure)
    BY ConditionalChoiceLoweringPreservesStepAndFailure, SMT
        DEF __SwiftTLAChoiceFailure0, __SwiftTLAAnyEvaluationFailure0,
            __SwiftTLAEvaluationOK,
            CompiledFailure, MatchingChoice, DefinedGuardedBranches

THEOREM EmittedSelectedBranchInstantiatesDefinedRule ==
    ASSUME attempt \in BOOLEAN
    PROVE /\ (select <=> pc = "select"
                /\ DefinedConditional(TRUE, attempt, TrueBranch, FalseBranch))
          /\ (__SwiftTLAChoiceFailure0 <=> pc = "select"
                /\ RenderedFirstFailure(TRUE, attempt, ~MatchingChoice, FALSE) = "yes")
    BY SelectedBranchPreservesCompleteStep,
        SelectedFailureAndCheckingInvariantAgree, SMT
        DEF SourceSelect, SourceFailure,
            DefinedConditional, RenderedFirstFailure,
            RenderedConditionFailure, RenderedYesFailure,
            RenderedNoFailure

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
            DefinedConditional, TrueBranch, FalseBranch, MatchingChoice,
            __SwiftTLAChoiceFailure0

WrongBranchFailure == pc = "select" /\ attempt = FALSE

THEOREM ReversedBranchFailureIsRejected ==
    ASSUME pc = "select", attempt = TRUE
    PROVE __SwiftTLAChoiceFailure0 /\ ~WrongBranchFailure
    BY SMT DEF __SwiftTLAChoiceFailure0, WrongBranchFailure

======================================================================
