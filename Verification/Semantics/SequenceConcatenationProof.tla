---------------- MODULE SequenceConcatenationProof ----------------
EXTENDS TLAPS, SequenceTheorems, SequenceConcatenationMachine

SourceConcatenation(left, right) ==
    [index \in 1..(Len(left) + Len(right)) |->
        IF index <= Len(left) THEN left[index] ELSE right[index - Len(left)]]

SourceInit == front = <<1>> /\ back = <<2, 2>>
SourceCombine ==
    Len(front) = 1 /\ front' = SourceConcatenation(front, back) /\ UNCHANGED back
SourceNext == SourceCombine
SourceBounded == Len(front) <= 3 /\ Len(back) = 2
SourceLabeled(label) == label = "combine" /\ SourceCombine
EmittedLabeled(label) == label = "combine" /\ combine

THEOREM ConcatenationHasSourceIndexOrder ==
    ASSUME NEW left \in Seq(Int), NEW right \in Seq(Int)
    PROVE SourceConcatenation(left, right) = left \o right
    BY ConcatProperties, SeqEqual, IsASeq, SMT DEF SourceConcatenation

THEOREM CompleteConcatenationStepPreserved ==
    ASSUME front \in Seq(Int), back \in Seq(Int), NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (combine <=> SourceCombine)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
          /\ (bounded <=> SourceBounded)
    <1>1. SourceConcatenation(front, back) = front \o back
        BY ConcatenationHasSourceIndexOrder
    <1>2. QED
        BY <1>1, SMT DEF Init, SourceInit, combine, SourceCombine,
            Next, SourceNext, EmittedLabeled, SourceLabeled,
            bounded, SourceBounded

THEOREM InitialConcatenationStateHasBound ==
    Init => front \in Seq(Int) /\ back \in Seq(Int) /\ SourceBounded
    BY SMT DEF Init, SourceBounded

THEOREM ConcatenationPreservesBound ==
    ASSUME front \in Seq(Int), back \in Seq(Int), SourceBounded, combine
    PROVE front' \in Seq(Int) /\ back' \in Seq(Int) /\ SourceBounded'
    BY ConcatProperties, SMT DEF SourceBounded, combine

THEOREM ConcatenationGuardControlsEnabledness ==
    ASSUME front \in Seq(Int), back \in Seq(Int)
    PROVE ENABLED combine <=> Len(front) = 1
    BY ConcatProperties, ExpandENABLED, SMT DEF combine

THEOREM ReversedOperandsChangeTheCompleteTarget ==
    ASSUME front = <<1>>, back = <<2, 2>>
    PROVE SourceConcatenation(front, back) /= back \o front
    <1>1. SourceConcatenation(front, back) = front \o back
        BY ConcatenationHasSourceIndexOrder, SMT
    <1>2. front \o back /= back \o front
        BY ConcatProperties, SMT
    <1>3. QED BY <1>1, <1>2

=====================================================================
