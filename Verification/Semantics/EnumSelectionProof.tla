--------------------- MODULE EnumSelectionProof ---------------------
EXTENDS TLAPS, Integers

Members == {"alpha", "zed"}
Rank(value) == CASE value = "alpha" -> 0 [] value = "zed" -> 1
Matches(predicate) == {member \in Members : predicate[member]}
CanonicalFirst(predicate) ==
    CHOOSE member \in Matches(predicate) :
        \A other \in Matches(predicate) : Rank(member) <= Rank(other)
NativeFirst(predicate) ==
    IF predicate["alpha"] THEN "alpha" ELSE "zed"

THEOREM CanonicalEnumSelectionMatchesSwiftOrder ==
    \A predicate \in [Members -> BOOLEAN] :
        Matches(predicate) # {} => CanonicalFirst(predicate) = NativeFirst(predicate)
    BY SMT DEF Members, Rank, Matches, CanonicalFirst, NativeFirst

THEOREM EmptyEnumSelectionHasMatchingFailure ==
    \A predicate \in [Members -> BOOLEAN] :
        Matches(predicate) = {}
            <=> ~predicate["alpha"] /\ ~predicate["zed"]
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
    IF state.pc = "select" /\ ~predicate["alpha"] /\ ~predicate["zed"]
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}
RenderedFailures(predicate, state) ==
    IF state.pc = "select" /\ Matches(predicate) = {}
    THEN {<<state, "select", "noSatisfyingChoice">>}
    ELSE {}

THEOREM EnumChoicePreservesCompleteEdgesAndFailures ==
    ASSUME NEW predicate \in [Members -> BOOLEAN],
           NEW state \in [pc: {"select", "Done"}, selected: Members]
    PROVE /\ NativeEdges(predicate, state) = RenderedEdges(predicate, state)
          /\ NativeFailures(predicate, state) = RenderedFailures(predicate, state)
    BY CanonicalEnumSelectionMatchesSwiftOrder,
        EmptyEnumSelectionHasMatchingFailure, SMT
        DEF NativeEdges, RenderedEdges, NativeFailures, RenderedFailures

ReversedFirst(predicate) ==
    CHOOSE member \in Matches(predicate) :
        \A other \in Matches(predicate) :
            (CASE member = "zed" -> 0 [] member = "alpha" -> 1)
                <= (CASE other = "zed" -> 0 [] other = "alpha" -> 1)

THEOREM ReversedEnumOrderChangesResult ==
    ReversedFirst([member \in Members |-> TRUE]) = "zed"
    BY SMT DEF ReversedFirst, Matches, Members

THEOREM ReversedEnumOrderChangesCompleteEdge ==
    ASSUME NEW state \in [pc: {"select", "Done"}, selected: Members],
           state.pc = "select"
    PROVE NativeEdges([member \in Members |-> TRUE], state)
        # {<<state, "select", [state EXCEPT !.pc = "Done", !.selected =
            ReversedFirst([member \in Members |-> TRUE])]>>}
    BY ReversedEnumOrderChangesResult, SMT
        DEF NativeEdges, NativeFirst, Matches, Members

=====================================================================
