--------------------- MODULE BooleanSelectionProof ---------------------
EXTENDS TLAPS, BooleanSelection

BooleanMatches(predicate) ==
    {member \in BOOLEAN : predicate[member]}
CanonicalBooleanFirst(predicate) ==
    CHOOSE member \in BooleanMatches(predicate) :
        \A other \in BooleanMatches(predicate) :
            member = FALSE \/ other = TRUE
NativeBooleanFirst(predicate) ==
    IF predicate[FALSE] THEN FALSE ELSE TRUE

THEOREM CanonicalBooleanFirstMatchesSortedFirst ==
    \A predicate \in [BOOLEAN -> BOOLEAN] :
        BooleanMatches(predicate) # {} =>
            CanonicalBooleanFirst(predicate) = NativeBooleanFirst(predicate)
    BY SMT DEF BooleanMatches, CanonicalBooleanFirst, NativeBooleanFirst

THEOREM BooleanFirstFailureMatchesEmptySet ==
    \A predicate \in [BOOLEAN -> BOOLEAN] :
        (~predicate[FALSE] /\ ~predicate[TRUE])
            <=> BooleanMatches(predicate) = {}
    BY SMT DEF BooleanMatches

THEOREM BooleanFirstOutcomeMatchesSource ==
    \A predicate \in [BOOLEAN -> BOOLEAN] :
        /\ (BooleanMatches(predicate) = {}
                <=> ~predicate[FALSE] /\ ~predicate[TRUE])
        /\ (BooleanMatches(predicate) # {}
                => CanonicalBooleanFirst(predicate) = NativeBooleanFirst(predicate))
    BY CanonicalBooleanFirstMatchesSortedFirst,
        BooleanFirstFailureMatchesEmptySet, SMT

THEOREM LeastBooleanChoice ==
    (CHOOSE member \in {FALSE, TRUE} :
        \A other \in {FALSE, TRUE} :
            member = FALSE \/ other = TRUE) = FALSE
    BY SMT

SourceInit == pc = "select" /\ flag = TRUE
SourceBooleanChoice ==
    pc = "select" /\ flag' = FALSE /\ pc' = "Done"
CompiledBooleanChoice ==
    pc = "select"
    /\ flag' = NativeBooleanFirst([member \in BOOLEAN |-> TRUE])
    /\ pc' = "Done"
SourceBooleanTerminating ==
    pc = "Done" /\ UNCHANGED <<pc, flag>>
SourceBooleanNext == SourceBooleanChoice \/ SourceBooleanTerminating
SourceLabeledChoice(label) == label = "select" /\ SourceBooleanChoice
CompiledLabeledChoice(label) == label = "select" /\ CompiledBooleanChoice
EmittedLabeledChoice(label) == label = "select" /\ select
SourceLabeledTerminating(label) ==
    label = "Terminating" /\ SourceBooleanTerminating
CompiledLabeledTerminating(label) ==
    label = "Terminating" /\ SourceBooleanTerminating
EmittedLabeledTerminating(label) ==
    label = "Terminating" /\ Terminating

THEOREM EmittedBooleanChoiceInitialState ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM EmittedBooleanChoiceMatchesSource ==
    select <=> SourceBooleanChoice
    BY LeastBooleanChoice, SMT DEF select, SourceBooleanChoice

THEOREM CompiledBooleanChoiceMatchesSource ==
    CompiledBooleanChoice <=> SourceBooleanChoice
    BY SMT DEF CompiledBooleanChoice, SourceBooleanChoice,
        NativeBooleanFirst

THEOREM EmittedBooleanChoiceHasNoFailure ==
    ~__SwiftTLAChoiceFailure0
    BY SMT DEF __SwiftTLAChoiceFailure0

THEOREM EmittedBooleanEvaluationCheckPasses ==
    __SwiftTLAEvaluationOK
    BY EmittedBooleanChoiceHasNoFailure
        DEF __SwiftTLAEvaluationOK

THEOREM EmittedBooleanTerminatingMatchesSource ==
    Terminating <=> SourceBooleanTerminating
    BY SMT DEF Terminating, SourceBooleanTerminating

THEOREM EmittedBooleanCompleteNext ==
    Next <=> SourceBooleanNext
    BY EmittedBooleanChoiceMatchesSource,
        EmittedBooleanTerminatingMatchesSource
        DEF Next, SourceBooleanNext

THEOREM CompleteBooleanSelectionSlice ==
    ASSUME NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (Next <=> SourceBooleanNext)
          /\ (SourceLabeledChoice(label)
                  <=> CompiledLabeledChoice(label))
          /\ (CompiledLabeledChoice(label)
                  <=> EmittedLabeledChoice(label))
          /\ (SourceLabeledTerminating(label)
                  <=> CompiledLabeledTerminating(label))
          /\ (CompiledLabeledTerminating(label)
                  <=> EmittedLabeledTerminating(label))
          /\ ~__SwiftTLAChoiceFailure0
          /\ __SwiftTLAEvaluationOK
    BY EmittedBooleanChoiceInitialState, EmittedBooleanCompleteNext,
        CompiledBooleanChoiceMatchesSource, EmittedBooleanChoiceMatchesSource,
        EmittedBooleanTerminatingMatchesSource, EmittedBooleanChoiceHasNoFailure,
        EmittedBooleanEvaluationCheckPasses, SMT
        DEF SourceLabeledChoice, CompiledLabeledChoice,
            EmittedLabeledChoice, SourceLabeledTerminating,
            CompiledLabeledTerminating, EmittedLabeledTerminating

THEOREM ReversedBooleanChoiceWouldChangeStep ==
    (CHOOSE member \in {FALSE, TRUE} :
        \A other \in {FALSE, TRUE} :
            member = TRUE \/ other = FALSE) = TRUE
    BY SMT

=======================================================================
