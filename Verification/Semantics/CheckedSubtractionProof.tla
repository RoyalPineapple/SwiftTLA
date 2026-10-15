------------------- MODULE CheckedSubtractionProof -------------------
EXTENDS Integers, TLAPS

CONSTANTS SwiftIntMin, SwiftIntMax
ASSUME SwiftIntBounds ==
    /\ SwiftIntMin \in Int
    /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= -2000000000
    /\ 2000000000 <= SwiftIntMax

WithinSwiftInt(value) == SwiftIntMin <= value /\ value <= SwiftIntMax
SmallOperands(lhs, rhs) ==
    /\ -1000000000 <= lhs /\ lhs <= 1000000000
    /\ -1000000000 <= rhs /\ rhs <= 1000000000

EmittedSubtractDefined(lhs, rhs) ==
    IF SmallOperands(lhs, rhs) THEN TRUE
    ELSE IF rhs > 0 THEN lhs >= SwiftIntMin + rhs
    ELSE IF rhs < 0 THEN lhs <= SwiftIntMax + rhs
    ELSE TRUE

NativeSubtractWouldOverflow(lhs, rhs) ==
    \/ (rhs > 0 /\ lhs < SwiftIntMin + rhs)
    \/ (rhs < 0 /\ lhs > SwiftIntMax + rhs)

THEOREM EmittedSubtractionGuardMatchesCheckedInt ==
    ASSUME NEW lhs \in Int, NEW rhs \in Int,
           WithinSwiftInt(lhs), WithinSwiftInt(rhs)
    PROVE EmittedSubtractDefined(lhs, rhs)
          <=> WithinSwiftInt(lhs - rhs)
    PROOF
    <1>0. USE SwiftIntBounds DEF SwiftIntBounds
    <1>1. SmallOperands(lhs, rhs) =>
            WithinSwiftInt(lhs - rhs)
        BY SMT DEF SmallOperands, WithinSwiftInt
    <1>2. rhs > 0 =>
            /\ lhs - rhs <= SwiftIntMax
            /\ (lhs - rhs >= SwiftIntMin
                <=> lhs >= SwiftIntMin + rhs)
        BY SMT DEF WithinSwiftInt
    <1>3. rhs < 0 =>
            /\ lhs - rhs >= SwiftIntMin
            /\ (lhs - rhs <= SwiftIntMax
                <=> lhs <= SwiftIntMax + rhs)
        BY SMT DEF WithinSwiftInt
    <1>4. rhs = 0 => WithinSwiftInt(lhs - rhs)
        BY SMT DEF WithinSwiftInt
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, SMT
        DEF EmittedSubtractDefined, SmallOperands, WithinSwiftInt

THEOREM NativeSubtractionGuardMatchesCheckedInt ==
    ASSUME NEW lhs \in Int, NEW rhs \in Int,
           WithinSwiftInt(lhs), WithinSwiftInt(rhs)
    PROVE NativeSubtractWouldOverflow(lhs, rhs)
          <=> ~WithinSwiftInt(lhs - rhs)
    PROOF
    <1>0. USE SwiftIntBounds DEF SwiftIntBounds
    <1>1. rhs > 0 => lhs - rhs <= SwiftIntMax
        BY SMT DEF WithinSwiftInt
    <1>2. rhs < 0 => lhs - rhs >= SwiftIntMin
        BY SMT DEF WithinSwiftInt
    <1>3. rhs > 0 =>
            (lhs - rhs < SwiftIntMin <=> lhs < SwiftIntMin + rhs)
        BY SMT
    <1>4. rhs < 0 =>
            (lhs - rhs > SwiftIntMax <=> lhs > SwiftIntMax + rhs)
        BY SMT
    <1>5. rhs = 0 => WithinSwiftInt(lhs - rhs)
        BY SMT DEF WithinSwiftInt
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, SMT
        DEF NativeSubtractWouldOverflow, WithinSwiftInt

InitialState(value) == [pc |-> "advance", count |-> value]
FinalState(value) == [pc |-> "Done", count |-> value]
LabeledEdge(lhs, rhs) ==
    <<InitialState(lhs), "advance", FinalState(lhs - rhs)>>
Failure(lhs, rhs) ==
    <<InitialState(lhs), "advance", "subtraction", <<lhs, rhs>>>>

SourceEdges(lhs, rhs) ==
    IF WithinSwiftInt(lhs - rhs) THEN {LabeledEdge(lhs, rhs)} ELSE {}
EmittedEdges(lhs, rhs) ==
    IF EmittedSubtractDefined(lhs, rhs) THEN {LabeledEdge(lhs, rhs)} ELSE {}
NativeEdges(lhs, rhs) ==
    IF NativeSubtractWouldOverflow(lhs, rhs) THEN {}
    ELSE {LabeledEdge(lhs, rhs)}

SourceFailures(lhs, rhs) ==
    IF WithinSwiftInt(lhs - rhs) THEN {} ELSE {Failure(lhs, rhs)}
EmittedFailures(lhs, rhs) ==
    IF EmittedSubtractDefined(lhs, rhs) THEN {} ELSE {Failure(lhs, rhs)}
NativeFailures(lhs, rhs) ==
    IF NativeSubtractWouldOverflow(lhs, rhs) THEN {Failure(lhs, rhs)}
    ELSE {}

THEOREM RootSubtractionPreservesLabeledEdgesAndFailures ==
    ASSUME NEW lhs \in Int, NEW rhs \in Int,
           WithinSwiftInt(lhs), WithinSwiftInt(rhs)
    PROVE /\ SourceEdges(lhs, rhs) = EmittedEdges(lhs, rhs)
          /\ SourceEdges(lhs, rhs) = NativeEdges(lhs, rhs)
          /\ SourceFailures(lhs, rhs) = EmittedFailures(lhs, rhs)
          /\ SourceFailures(lhs, rhs) = NativeFailures(lhs, rhs)
    BY EmittedSubtractionGuardMatchesCheckedInt,
       NativeSubtractionGuardMatchesCheckedInt, SMT
       DEF SourceEdges, EmittedEdges, NativeEdges,
           SourceFailures, EmittedFailures, NativeFailures

THEOREM OmittingTheGuardAddsAnInvalidLabeledEdge ==
    ASSUME WithinSwiftInt(SwiftIntMax), WithinSwiftInt(-1)
    PROVE SourceEdges(SwiftIntMax, -1)
           # {LabeledEdge(SwiftIntMax, -1)}
    BY SwiftIntBounds, SMT
        DEF SourceEdges, WithinSwiftInt, SwiftIntBounds

=============================================================================
