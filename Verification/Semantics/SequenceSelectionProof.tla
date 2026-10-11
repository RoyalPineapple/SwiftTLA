------------------- MODULE SequenceSelectionProof -------------------
EXTENDS TLAPS, SequenceSelection

Members == {<<1>>, <<1, 0>>, <<2>>}
Rank(value) ==
    CASE value = <<1>> -> 0
      [] value = <<1, 0>> -> 1
      [] value = <<2>> -> 2
Matches(predicate) == {member \in Members : predicate[member]}
CanonicalFirst(predicate) ==
    CHOOSE member \in Matches(predicate) :
        \A other \in Matches(predicate) : Rank(member) <= Rank(other)
NativeFirst(predicate) ==
    IF predicate[<<1>>] THEN <<1>>
    ELSE IF predicate[<<1, 0>>] THEN <<1, 0>> ELSE <<2>>

THEOREM CanonicalSequenceChoiceMatchesSwiftOrder ==
    \A predicate \in [Members -> BOOLEAN] :
        Matches(predicate) # {} => CanonicalFirst(predicate) = NativeFirst(predicate)
    BY SMT DEF Members, Rank, Matches, CanonicalFirst, NativeFirst

THEOREM EmptySequenceChoiceHasMatchingFailure ==
    \A predicate \in [Members -> BOOLEAN] :
        Matches(predicate) = {}
            <=> ~predicate[<<1>>] /\ ~predicate[<<1, 0>>] /\ ~predicate[<<2>>]
    BY SMT DEF Members, Matches

SourceEdges(predicate, state) ==
    IF state.pc = "select" /\ Matches(predicate) # {}
    THEN {<<state, "select",
            [state EXCEPT !.pc = "Done", !.selected = NativeFirst(predicate)]>>}
    ELSE {}
RenderedEdges(predicate, state) ==
    IF state.pc = "select" /\ Matches(predicate) # {}
    THEN {<<state, "select",
            [state EXCEPT !.pc = "Done", !.selected = CanonicalFirst(predicate)]>>}
    ELSE {}
SourceFailures(predicate, state) ==
    IF state.pc = "select"
        /\ ~predicate[<<1>>] /\ ~predicate[<<1, 0>>] /\ ~predicate[<<2>>]
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}
RenderedFailures(predicate, state) ==
    IF state.pc = "select" /\ Matches(predicate) = {}
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}

THEOREM SequenceChoicePreservesCompleteEdgesAndFailures ==
    ASSUME NEW predicate \in [Members -> BOOLEAN],
           NEW state \in [pc: {"select", "Done"}, selected: Members]
    PROVE /\ SourceEdges(predicate, state) = RenderedEdges(predicate, state)
          /\ SourceFailures(predicate, state) = RenderedFailures(predicate, state)
    BY CanonicalSequenceChoiceMatchesSwiftOrder,
        EmptySequenceChoiceHasMatchingFailure, SMT
        DEF SourceEdges, RenderedEdges, SourceFailures, RenderedFailures

ReversedFirst(predicate) ==
    CHOOSE member \in Matches(predicate) :
        \A other \in Matches(predicate) :
            (CASE member = <<2>> -> 0
               [] member = <<1, 0>> -> 1
               [] member = <<1>> -> 2)
                <= (CASE other = <<2>> -> 0
                   [] other = <<1, 0>> -> 1
                   [] other = <<1>> -> 2)

THEOREM ReversedSequenceOrderChangesCompleteEdge ==
    ASSUME NEW state \in [pc: {"select", "Done"}, selected: Members],
           state.pc = "select"
    PROVE SourceEdges([member \in Members |-> TRUE], state)
        # {<<state, "select", [state EXCEPT !.pc = "Done", !.selected =
            ReversedFirst([member \in Members |-> TRUE])]>>}
    BY SMT DEF SourceEdges, NativeFirst, ReversedFirst, Matches, Members

SourceInit == pc = "select" /\ selected = <<2>>
SourceSelect == pc = "select" /\ selected' = <<1>> /\ pc' = "Done"
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, selected>>
SourceNext == SourceSelect \/ SourceTerminating
SourceLabeledSelect(label) == label = "select" /\ SourceSelect
SourceLabeledTerminating(label) ==
    label = "Terminating" /\ SourceTerminating
EmittedLabeledSelect(label) == label = "select" /\ select
EmittedLabeledTerminating(label) ==
    label = "Terminating" /\ Terminating

THEOREM EmittedSequenceChoiceMatchesSource ==
    select <=> SourceSelect
    BY CanonicalSequenceChoiceMatchesSwiftOrder, SMT
        DEF select, SourceSelect, CanonicalFirst, NativeFirst, Matches, Members, Rank

THEOREM CompleteEmittedSequenceSelection ==
    ASSUME NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (Next <=> SourceNext)
          /\ (SourceLabeledSelect(label) <=> EmittedLabeledSelect(label))
          /\ (SourceLabeledTerminating(label)
                <=> EmittedLabeledTerminating(label))
          /\ ~__SwiftTLAChoiceFailure0
          /\ __SwiftTLAEvaluationOK
    BY EmittedSequenceChoiceMatchesSource, SMT
        DEF Init, SourceInit, Next, SourceNext, Terminating,
            SourceTerminating, SourceLabeledSelect, EmittedLabeledSelect,
            SourceLabeledTerminating, EmittedLabeledTerminating,
            __SwiftTLAChoiceFailure0, __SwiftTLAEvaluationOK

=====================================================================
