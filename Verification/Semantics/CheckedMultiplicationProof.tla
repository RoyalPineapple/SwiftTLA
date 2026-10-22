------------------ MODULE CheckedMultiplicationProof ------------------
EXTENDS Integers, TLAPS

CONSTANTS SwiftIntMin, SwiftIntMax
ASSUME SwiftIntBounds ==
    /\ SwiftIntMin \in Int
    /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= -2000000000
    /\ 2000000000 <= SwiftIntMax

WithinSwiftInt(value) == SwiftIntMin <= value /\ value <= SwiftIntMax
SmallOperands(lhs, rhs) ==
    /\ -40000 <= lhs /\ lhs <= 40000
    /\ -40000 <= rhs /\ rhs <= 40000

EmittedMultiplyDefined(lhs, rhs) ==
    IF SmallOperands(lhs, rhs) THEN TRUE
    ELSE WithinSwiftInt(lhs * rhs)

THEOREM SmallProductFitsSwiftInt ==
    ASSUME NEW lhs \in Int, NEW rhs \in Int,
           SmallOperands(lhs, rhs)
    PROVE WithinSwiftInt(lhs * rhs)
    BY SwiftIntBounds, SMT
        DEF SmallOperands, WithinSwiftInt, SwiftIntBounds

THEOREM EmittedMultiplicationGuardMatchesCheckedInt ==
    ASSUME NEW lhs \in Int, NEW rhs \in Int
    PROVE EmittedMultiplyDefined(lhs, rhs)
          <=> WithinSwiftInt(lhs * rhs)
    BY SmallProductFitsSwiftInt, SMT
        DEF EmittedMultiplyDefined, SmallOperands, WithinSwiftInt

InitialState(value) == [pc |-> "advance", count |-> value]
FinalState(value) == [pc |-> "Done", count |-> value]
LabeledEdge(lhs, rhs) ==
    <<InitialState(lhs), "advance", FinalState(lhs * rhs)>>
Failure(lhs, rhs) ==
    <<InitialState(lhs), "advance", "multiplication", <<lhs, rhs>>>>

SourceEdges(lhs, rhs) ==
    IF WithinSwiftInt(lhs * rhs) THEN {LabeledEdge(lhs, rhs)} ELSE {}
EmittedEdges(lhs, rhs) ==
    IF EmittedMultiplyDefined(lhs, rhs) THEN {LabeledEdge(lhs, rhs)} ELSE {}
ModeledNativeEdges(lhs, rhs) ==
    IF WithinSwiftInt(lhs * rhs) THEN {LabeledEdge(lhs, rhs)} ELSE {}

SourceFailures(lhs, rhs) ==
    IF WithinSwiftInt(lhs * rhs) THEN {} ELSE {Failure(lhs, rhs)}
EmittedFailures(lhs, rhs) ==
    IF EmittedMultiplyDefined(lhs, rhs) THEN {} ELSE {Failure(lhs, rhs)}
ModeledNativeFailures(lhs, rhs) ==
    IF WithinSwiftInt(lhs * rhs) THEN {} ELSE {Failure(lhs, rhs)}

THEOREM RootMultiplicationPreservesLabeledEdgesAndFailures ==
    ASSUME NEW lhs \in Int, NEW rhs \in Int,
           WithinSwiftInt(lhs), WithinSwiftInt(rhs)
    PROVE /\ SourceEdges(lhs, rhs) = EmittedEdges(lhs, rhs)
          /\ SourceEdges(lhs, rhs) = ModeledNativeEdges(lhs, rhs)
          /\ SourceFailures(lhs, rhs) = EmittedFailures(lhs, rhs)
          /\ SourceFailures(lhs, rhs) = ModeledNativeFailures(lhs, rhs)
    BY EmittedMultiplicationGuardMatchesCheckedInt, SMT
       DEF SourceEdges, EmittedEdges, ModeledNativeEdges,
           SourceFailures, EmittedFailures, ModeledNativeFailures

THEOREM OmittingTheGuardAddsAnInvalidLabeledEdge ==
    ASSUME WithinSwiftInt(SwiftIntMax), WithinSwiftInt(2)
    PROVE SourceEdges(SwiftIntMax, 2)
           # {LabeledEdge(SwiftIntMax, 2)}
    BY SwiftIntBounds, SMT
        DEF SourceEdges, WithinSwiftInt, SwiftIntBounds

=======================================================================
