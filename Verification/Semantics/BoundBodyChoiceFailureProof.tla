---------------- MODULE BoundBodyChoiceFailureProof ----------------
EXTENDS TLAPS, BoundBodyChoiceFailureModel, DefinedActionFailureRule

SourceHasChoice == \E member \in {1} : member = source
SourceInit == source \in 0..1 /\ result = 0
SourcePick == SourceHasChoice /\ source' = source /\ result' = 1
SourceFailure == ~SourceHasChoice
SourceEvaluationOK == ~SourceFailure
SourceLabeled(label) == label = "pick" /\ SourcePick
EmittedLabeled(label) == label = "pick" /\ pick

THEOREM EmittedInitialStatesMatchSource ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM EmittedBoundChoiceMatchesSource ==
    ASSUME SourceHasChoice
    PROVE pick <=> SourcePick
    BY SMT DEF pick, SourcePick, SourceHasChoice

THEOREM EmittedStepMatchesSource ==
    pick <=> SourcePick
    BY EmittedBoundChoiceMatchesSource, SMT
        DEF pick, SourcePick, SourceHasChoice

THEOREM EmittedFailureAndCheckMatchSource ==
    /\ __SwiftTLAChoiceFailure0 <=> SourceFailure
    /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY SMT DEF __SwiftTLAChoiceFailure0, __SwiftTLAEvaluationOK,
        SourceFailure, SourceEvaluationOK, SourceHasChoice

THEOREM CompleteLabeledOutcomeMatchesSource ==
    ASSUME NEW label
    PROVE /\ Init <=> SourceInit
          /\ EmittedLabeled(label) <=> SourceLabeled(label)
          /\ Next <=> SourcePick
          /\ __SwiftTLAChoiceFailure0 <=> SourceFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedInitialStatesMatchSource, EmittedStepMatchesSource,
        EmittedFailureAndCheckMatchSource, SMT
        DEF EmittedLabeled, SourceLabeled, Next

OmittedBodyFailure == FALSE

THEOREM OmittedBodyFailureIsDetectedAtInitialState ==
    ASSUME source = 0, result = 0
    PROVE /\ SourceInit
          /\ SourceFailure
          /\ ~__SwiftTLAEvaluationOK
          /\ ~OmittedBodyFailure
    BY Isa DEF SourceInit, SourceFailure, SourceHasChoice,
        __SwiftTLAChoiceFailure0, __SwiftTLAEvaluationOK,
        OmittedBodyFailure

===================================================================
