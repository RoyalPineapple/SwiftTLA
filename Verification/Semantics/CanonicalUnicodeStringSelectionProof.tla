---- MODULE CanonicalUnicodeStringSelectionProof ---------------------
EXTENDS TLAPS, Integers, CanonicalUnicodeStringSelection

Members == {"z", "é"}
Rank(value) == CASE value = "z" -> 0 [] value = "é" -> 1
Matches(predicate) == {member \in Members : predicate[member]}
CanonicalFirst(predicate) ==
    CHOOSE member \in Matches(predicate) :
        \A other \in Matches(predicate) : Rank(member) <= Rank(other)
NativeFirst(predicate) ==
    IF predicate["z"] THEN "z" ELSE "é"

THEOREM CanonicalUnicodeStringSelectionMatchesSwiftOrder ==
    \A predicate \in [Members -> BOOLEAN] :
        Matches(predicate) # {} => CanonicalFirst(predicate) = NativeFirst(predicate)
    BY SMT DEF Members, Rank, Matches, CanonicalFirst, NativeFirst

THEOREM EmptyCanonicalUnicodeStringSelectionHasMatchingFailure ==
    \A predicate \in [Members -> BOOLEAN] :
        Matches(predicate) = {}
            <=> ~predicate["z"] /\ ~predicate["é"]
    BY SMT DEF Members, Matches

NativeEdges(predicate, state) ==
    IF state.pc = "select" /\ Matches(predicate) # {}
    THEN {<<state, "select",
            [state EXCEPT !.pc = "Done", !.selected = NativeFirst(predicate)]>>}
    ELSE {}
RenderedEdges(predicate, state) ==
    IF state.pc = "select" /\ Matches(predicate) # {}
    THEN {<<state, "select",
            [state EXCEPT !.pc = "Done", !.selected = CanonicalFirst(predicate)]>>}
    ELSE {}
NativeFailures(predicate, state) ==
    IF state.pc = "select" /\ ~predicate["z"] /\ ~predicate["é"]
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}
RenderedFailures(predicate, state) ==
    IF state.pc = "select" /\ Matches(predicate) = {}
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}

THEOREM UnicodeStringChoicePreservesCompleteEdgesAndFailures ==
    ASSUME NEW predicate \in [Members -> BOOLEAN],
           NEW state \in [pc: {"select", "Done"}, selected: Members]
    PROVE /\ NativeEdges(predicate, state) = RenderedEdges(predicate, state)
          /\ NativeFailures(predicate, state) = RenderedFailures(predicate, state)
    BY CanonicalUnicodeStringSelectionMatchesSwiftOrder,
        EmptyCanonicalUnicodeStringSelectionHasMatchingFailure, SMT
        DEF NativeEdges, RenderedEdges, NativeFailures, RenderedFailures

ReversedFirst(predicate) ==
    CHOOSE member \in Matches(predicate) :
        \A other \in Matches(predicate) :
            (CASE member = "é" -> 0 [] member = "z" -> 1)
                <= (CASE other = "é" -> 0 [] other = "z" -> 1)

THEOREM ReversedUnicodeStringOrderChangesResult ==
    ReversedFirst([member \in Members |-> TRUE]) = "é"
    BY SMT DEF ReversedFirst, Matches, Members

THEOREM ReversedUnicodeStringOrderChangesCompleteEdge ==
    ASSUME NEW state \in [pc: {"select", "Done"}, selected: Members],
           state.pc = "select"
    PROVE NativeEdges([member \in Members |-> TRUE], state)
        # {<<state, "select", [state EXCEPT !.pc = "Done", !.selected =
            ReversedFirst([member \in Members |-> TRUE])]>>}
    BY ReversedUnicodeStringOrderChangesResult, SMT
        DEF NativeEdges, NativeFirst, Matches, Members

SourceInit == pc = "select" /\ selected = "é"
SourceSelect == pc = "select" /\ selected' = "z" /\ pc' = "Done"
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, selected>>
SourceNext == SourceSelect \/ SourceTerminating
SourceLabeledSelect(label) == label = "select" /\ SourceSelect
SourceLabeledTerminating(label) ==
    label = "Terminating" /\ SourceTerminating
EmittedLabeledSelect(label) == label = "select" /\ select
EmittedLabeledTerminating(label) ==
    label = "Terminating" /\ Terminating

THEOREM EmittedUnicodeStringChoiceMatchesSource ==
    select <=> SourceSelect
    BY CanonicalUnicodeStringSelectionMatchesSwiftOrder, SMT
        DEF select, SourceSelect, CanonicalFirst, NativeFirst, Matches, Members, Rank

THEOREM EmittedUnicodeStringChoiceHasNoFailure ==
    ~__SwiftTLAChoiceFailure0
    BY SMT DEF __SwiftTLAChoiceFailure0

THEOREM CompleteEmittedCanonicalUnicodeStringSelection ==
    ASSUME NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (Next <=> SourceNext)
          /\ (SourceLabeledSelect(label) <=> EmittedLabeledSelect(label))
          /\ (SourceLabeledTerminating(label)
                <=> EmittedLabeledTerminating(label))
          /\ ~__SwiftTLAChoiceFailure0
          /\ __SwiftTLAEvaluationOK
    BY EmittedUnicodeStringChoiceMatchesSource, EmittedUnicodeStringChoiceHasNoFailure, SMT
        DEF Init, SourceInit, Next, SourceNext, Terminating,
            SourceTerminating, SourceLabeledSelect, EmittedLabeledSelect,
            SourceLabeledTerminating, EmittedLabeledTerminating,
            __SwiftTLAEvaluationOK

=====================================================================
