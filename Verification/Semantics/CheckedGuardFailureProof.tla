------------------- MODULE CheckedGuardFailureProof -------------------
EXTENDS Integers, TLAPS

CONSTANTS SwiftIntMin, SwiftIntMax
ASSUME SwiftIntBounds ==
    /\ SwiftIntMin \in Int
    /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= -2000000000
    /\ 2000000000 <= SwiftIntMax

WithinSwiftInt(value) == SwiftIntMin <= value /\ value <= SwiftIntMax
SourceGuard(count) == WithinSwiftInt(count + 1) /\ count + 1 > 0
EmittedDefined(count) ==
    IF -1000000000 <= count /\ count <= 1000000000
    THEN TRUE
    ELSE count <= SwiftIntMax - 1
EmittedGuard(count) ==
    IF EmittedDefined(count) THEN count + 1 > 0 ELSE FALSE

InitialState(count) == [pc |-> "advance", count |-> count]
FinalState == [pc |-> "Done", count |-> 0]
LabeledEdge(count) == <<InitialState(count), "advance", FinalState>>
Failure(count) ==
    <<InitialState(count), "advance", "addition", <<count, 1>>>>

SourceEdges(count) == IF SourceGuard(count) THEN {LabeledEdge(count)} ELSE {}
EmittedEdges(count) == IF EmittedGuard(count) THEN {LabeledEdge(count)} ELSE {}
NativeEdges(count) == IF SourceGuard(count) THEN {LabeledEdge(count)} ELSE {}
SourceFailures(count) ==
    IF WithinSwiftInt(count + 1) THEN {} ELSE {Failure(count)}
EmittedFailures(count) ==
    IF EmittedDefined(count) THEN {} ELSE {Failure(count)}
NativeFailures(count) ==
    IF WithinSwiftInt(count + 1) THEN {} ELSE {Failure(count)}
SourceEvaluationOK(count) == SourceFailures(count) = {}
EmittedEvaluationOK(count) == EmittedFailures(count) = {}

THEOREM EmittedGuardDefinednessMatchesCheckedInt ==
    ASSUME NEW count \in Int, WithinSwiftInt(count)
    PROVE EmittedDefined(count) <=> WithinSwiftInt(count + 1)
    BY SwiftIntBounds, SMT
        DEF EmittedDefined, WithinSwiftInt, SwiftIntBounds

THEOREM GuardPreservesCompleteLabeledEdgesAndFailures ==
    ASSUME NEW count \in Int, WithinSwiftInt(count)
    PROVE /\ SourceEdges(count) = EmittedEdges(count)
          /\ SourceEdges(count) = NativeEdges(count)
          /\ SourceFailures(count) = EmittedFailures(count)
          /\ SourceFailures(count) = NativeFailures(count)
          /\ (SourceEvaluationOK(count) <=> EmittedEvaluationOK(count))
    BY EmittedGuardDefinednessMatchesCheckedInt, SMT
        DEF SourceGuard, EmittedGuard,
        SourceEdges, EmittedEdges, NativeEdges,
        SourceFailures, EmittedFailures, NativeFailures,
        SourceEvaluationOK, EmittedEvaluationOK

THEOREM OverflowingGuardHasFailureAndNoEdge ==
    ASSUME SwiftIntBounds
    PROVE /\ SourceEdges(SwiftIntMax) = {}
          /\ SourceFailures(SwiftIntMax) = {Failure(SwiftIntMax)}
    BY SMT DEF SourceEdges, SourceFailures, SourceGuard,
        WithinSwiftInt, SwiftIntBounds

THEOREM OmittingGuardDefinednessAddsInvalidEdge ==
    ASSUME SwiftIntBounds
    PROVE SourceEdges(SwiftIntMax) # {LabeledEdge(SwiftIntMax)}
    BY OverflowingGuardHasFailureAndNoEdge
        DEF SourceEdges

=======================================================================
