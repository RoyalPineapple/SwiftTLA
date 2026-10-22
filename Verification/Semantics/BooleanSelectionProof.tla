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

SourceBooleanRuleEdges(predicate, state) ==
    IF state.pc # "select" THEN {}
    ELSE IF predicate[FALSE] THEN
        {<<state, "select", [state EXCEPT !.pc = "Done", !.flag = FALSE]>>}
    ELSE IF predicate[TRUE] THEN
        {<<state, "select", [state EXCEPT !.pc = "Done", !.flag = TRUE]>>}
    ELSE {}
CompiledBooleanRuleEdges(predicate, state) ==
    IF state.pc = "select" /\ (predicate[FALSE] \/ predicate[TRUE])
    THEN {<<state, "select",
            [state EXCEPT !.pc = "Done", !.flag = NativeBooleanFirst(predicate)]>>}
    ELSE {}
RenderedBooleanRuleEdges(predicate, state) ==
    IF state.pc = "select" /\ BooleanMatches(predicate) # {}
    THEN {<<state, "select",
            [state EXCEPT !.pc = "Done", !.flag = CanonicalBooleanFirst(predicate)]>>}
    ELSE {}
SourceBooleanRuleFailures(predicate, state) ==
    IF state.pc = "select" /\ ~predicate[FALSE] /\ ~predicate[TRUE]
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}
RenderedBooleanRuleFailures(predicate, state) ==
    IF state.pc = "select" /\ BooleanMatches(predicate) = {}
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}

THEOREM BooleanChoiceRulePreservesCompleteEdgesAndFailures ==
    ASSUME NEW predicate \in [BOOLEAN -> BOOLEAN],
           NEW state \in [pc: {"select", "Done"}, flag: BOOLEAN]
    PROVE /\ SourceBooleanRuleEdges(predicate, state)
                = CompiledBooleanRuleEdges(predicate, state)
          /\ CompiledBooleanRuleEdges(predicate, state)
                = RenderedBooleanRuleEdges(predicate, state)
          /\ SourceBooleanRuleFailures(predicate, state)
                = RenderedBooleanRuleFailures(predicate, state)
    PROOF
    <1>1. BooleanMatches(predicate) # {}
            <=> predicate[FALSE] \/ predicate[TRUE]
        BY BooleanFirstFailureMatchesEmptySet, SMT DEF BooleanMatches
    <1>2. SourceBooleanRuleEdges(predicate, state)
            = CompiledBooleanRuleEdges(predicate, state)
        BY <1>1, SMT DEF SourceBooleanRuleEdges,
            CompiledBooleanRuleEdges, NativeBooleanFirst
    <1>3. CompiledBooleanRuleEdges(predicate, state)
            = RenderedBooleanRuleEdges(predicate, state)
        BY <1>1, CanonicalBooleanFirstMatchesSortedFirst, SMT
            DEF CompiledBooleanRuleEdges, RenderedBooleanRuleEdges
    <1>4. SourceBooleanRuleFailures(predicate, state)
            = RenderedBooleanRuleFailures(predicate, state)
        BY <1>1, SMT DEF SourceBooleanRuleFailures,
            RenderedBooleanRuleFailures
    <1>. QED BY <1>2, <1>3, <1>4

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
        DEF __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

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
          /\ ~__SwiftTLAAnyEvaluationFailure0
          /\ __SwiftTLAEvaluationOK
    BY EmittedBooleanChoiceInitialState, EmittedBooleanCompleteNext,
        CompiledBooleanChoiceMatchesSource, EmittedBooleanChoiceMatchesSource,
        EmittedBooleanTerminatingMatchesSource, EmittedBooleanChoiceHasNoFailure,
        EmittedBooleanEvaluationCheckPasses, SMT
        DEF SourceLabeledChoice, CompiledLabeledChoice,
            EmittedLabeledChoice, SourceLabeledTerminating,
            CompiledLabeledTerminating, EmittedLabeledTerminating,
            __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

ReversedBooleanFirst(predicate) ==
    CHOOSE member \in BooleanMatches(predicate) :
        \A other \in BooleanMatches(predicate) :
            member = TRUE \/ other = FALSE

THEOREM ReversedBooleanChoiceWouldChangeStep ==
    ReversedBooleanFirst([member \in BOOLEAN |-> TRUE]) = TRUE
    BY SMT DEF ReversedBooleanFirst, BooleanMatches

WrongBooleanRuleEdges(state) ==
    {<<state, "select", [state EXCEPT !.pc = "Done",
        !.flag = ReversedBooleanFirst([member \in BOOLEAN |-> TRUE])]>>}

THEOREM ReversedBooleanOrderChangesCompleteEdge ==
    ASSUME NEW state \in [pc: {"select", "Done"}, flag: BOOLEAN],
           state.pc = "select"
    PROVE SourceBooleanRuleEdges([member \in BOOLEAN |-> TRUE], state)
            # WrongBooleanRuleEdges(state)
    PROOF
    <1>1. BooleanMatches([member \in BOOLEAN |-> TRUE]) # {}
        BY SMT DEF BooleanMatches
    <1>2. NativeBooleanFirst([member \in BOOLEAN |-> TRUE]) = FALSE
        BY SMT DEF NativeBooleanFirst
    <1>3. [state EXCEPT !.pc = "Done", !.flag = FALSE]
            # [state EXCEPT !.pc = "Done", !.flag = TRUE]
        BY SMT
    <1>. QED BY <1>1, <1>2, <1>3,
        ReversedBooleanChoiceWouldChangeStep, SMT
        DEF SourceBooleanRuleEdges, WrongBooleanRuleEdges

=======================================================================
