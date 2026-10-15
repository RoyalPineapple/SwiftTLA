---------------- MODULE BoundBodyChoiceFailureProof ----------------
EXTENDS TLAPS, BoundBodyChoiceFailureModel, DefinedActionFailureRule

SourceHasChoice == \E member \in {1} : member = source
SourceInit == source \in 0..1 /\ result = 0
SourcePick == SourceHasChoice /\ source' = source /\ result' = 1
SourceFailure == ~SourceHasChoice
SourceEvaluationOK == ~SourceFailure
SourceLabeled(label) == label = "pick" /\ SourcePick
EmittedLabeled(label) == label = "pick" /\ pick

BoundStates == {<<0, 0>>, <<0, 1>>, <<1, 0>>, <<1, 1>>}
BoundUpdates == [candidate \in 0..1 |->
    IF candidate = 1 THEN {<<source, 1>>} ELSE {}]
BoundFailures == [candidate \in 0..1 |-> candidate # 1]
BoundSourceOutcome ==
    SourceCompleteOutcome(TRUE, source, BoundUpdates, BoundFailures,
        <<source, result>>, "pick")
BoundRenderedOutcome ==
    RenderedCompleteOutcome(TRUE, source, BoundUpdates, BoundFailures,
        <<source, result>>, "pick")

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
    BY SMT DEF __SwiftTLAChoiceFailure0,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK,
        SourceFailure, SourceEvaluationOK, SourceHasChoice

THEOREM BoundBodyInstantiatesCompositionalRule ==
    ASSUME source \in 0..1, result \in 0..1
    PROVE BoundSourceOutcome = BoundRenderedOutcome
    PROOF
    <1>1. BoundUpdates \in [0..1 -> SUBSET BoundStates]
        BY SMT DEF BoundUpdates, BoundStates
    <1>2. BoundFailures \in [0..1 -> BOOLEAN]
        BY SMT DEF BoundFailures
    <1>3. <<source, result>> \in BoundStates
        BY SMT DEF BoundStates
    <1>. QED
        BY DefinedActionComposesCompleteLabeledOutcomes,
            <1>1, <1>2, <1>3, SMT
            DEF BoundSourceOutcome, BoundRenderedOutcome

THEOREM BoundSourceOutcomeMatchesActualEmittedAction ==
    ASSUME source \in 0..1, result \in 0..1,
           source' \in 0..1, result' \in 0..1
    PROVE /\ (<<<<source, result>>, "pick", <<source', result'>>>>
                 \in BoundSourceOutcome.edges <=> pick)
          /\ (BoundSourceOutcome.failure = "body"
                 <=> __SwiftTLAChoiceFailure0)
    BY EmittedStepMatchesSource, EmittedFailureAndCheckMatchSource, SMT
        DEF BoundSourceOutcome, SourceCompleteOutcome,
            SourceLabeledEdges, SourceFirstFailure,
            BoundUpdates, BoundFailures, SourcePick,
            SourceFailure, SourceHasChoice

THEOREM ComposedBoundOutcomeMatchesActualEmittedAction ==
    ASSUME source \in 0..1, result \in 0..1,
           source' \in 0..1, result' \in 0..1
    PROVE /\ (<<<<source, result>>, "pick", <<source', result'>>>>
                 \in BoundRenderedOutcome.edges <=> pick)
          /\ (BoundRenderedOutcome.failure = "body"
                 <=> __SwiftTLAChoiceFailure0)
    BY BoundBodyInstantiatesCompositionalRule,
        BoundSourceOutcomeMatchesActualEmittedAction, SMT

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
OmittedBodyUpdates == [candidate \in 0..1 |-> {}]

THEOREM OmittingBoundBodyEdgeIsRejected ==
    ASSUME source = 1, result = 0
    PROVE SourceLabeledEdges(TRUE, source, BoundUpdates,
              <<source, result>>, "pick")
          # RenderedLabeledEdges(TRUE, source, OmittedBodyUpdates,
              <<source, result>>, "pick")
    BY SMT DEF SourceLabeledEdges, RenderedLabeledEdges,
        BoundUpdates, OmittedBodyUpdates

THEOREM OmittedBodyFailureIsDetectedAtInitialState ==
    ASSUME source = 0, result = 0
    PROVE /\ SourceInit
          /\ SourceFailure
          /\ ~__SwiftTLAEvaluationOK
          /\ ~OmittedBodyFailure
    BY Isa DEF SourceInit, SourceFailure, SourceHasChoice,
        __SwiftTLAChoiceFailure0, __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAEvaluationOK,
        OmittedBodyFailure

===================================================================
