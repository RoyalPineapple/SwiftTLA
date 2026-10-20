---------------- MODULE FallibleSequenceConcatenationProof ----------------
EXTENDS TLAPS, SequenceTheorems, FallibleSequenceConcatenationMachine

SourcePrefixValue(value, length) ==
    IF length < 1 THEN <<>> ELSE [index \in 1..length |-> value[index]]
CompiledPrefixValue(value, length) == SubSeq(value, 1, length)
SourceConcatenation(left, right) ==
    [index \in 1..(Len(left) + Len(right)) |->
        IF index <= Len(left) THEN left[index] ELSE right[index - Len(left)]]

SourceInit ==
    /\ front = <<1>>
    /\ back = <<2, 2>>
    /\ frontLength \in 1..2
    /\ backLength \in 2..3
SourceLeftDefined == frontLength <= Len(front)
SourceRightDefined == backLength <= Len(back)
SourceDefined == SourceLeftDefined /\ SourceRightDefined
SourceCombine ==
    IF SourceDefined
    THEN /\ front' = SourceConcatenation(
                    SourcePrefixValue(front, frontLength),
                    SourcePrefixValue(back, backLength))
         /\ UNCHANGED <<back, frontLength, backLength>>
    ELSE FALSE
SourceNext == SourceCombine
SourceLabeled(label) == label = "combine" /\ SourceCombine
EmittedLabeled(label) == label = "combine" /\ combine
SourceLeftFailure == ~SourceLeftDefined
SourceRightFailure == SourceLeftDefined /\ ~SourceRightDefined
SourceEvaluationOK == ~(SourceLeftFailure \/ SourceRightFailure)

THEOREM PrefixPreservesSourceIndices ==
    ASSUME NEW value \in Seq(Int), NEW length \in Int,
           length <= Len(value)
    PROVE SourcePrefixValue(value, length) = CompiledPrefixValue(value, length)
    PROOF
    <1>1. CASE length < 1
        <2>1. SourcePrefixValue(value, length) = <<>>
            BY <1>1, SMT DEF SourcePrefixValue
        <2>2. CompiledPrefixValue(value, length) = <<>>
            BY <1>1, SubSeqEmpty, SMT DEF CompiledPrefixValue
        <2>3. QED BY <2>1, <2>2
    <1>2. CASE length >= 1
        <2>1. length \in 0..Len(value) BY <1>2, SMT
        <2>2. CompiledPrefixValue(value, length) = Restrict(value, 1..length)
            BY SubSeqRestrict, <2>1 DEF CompiledPrefixValue
        <2>3. SourcePrefixValue(value, length) = Restrict(value, 1..length)
            BY <1>2, SMT DEF SourcePrefixValue, Restrict
        <2>4. QED BY <2>2, <2>3
    <1>3. QED BY <1>1, <1>2, SMT

THEOREM ConcatenationPreservesSourceIndices ==
    ASSUME NEW left \in Seq(Int), NEW right \in Seq(Int)
    PROVE SourceConcatenation(left, right) = left \o right
    BY ConcatProperties, SeqEqual, IsASeq, SMT DEF SourceConcatenation

THEOREM DefinedConcatenationValuePreserved ==
    ASSUME front \in Seq(Int), back \in Seq(Int),
           frontLength \in Int, backLength \in Int, SourceDefined
    PROVE SourceConcatenation(
                SourcePrefixValue(front, frontLength),
                SourcePrefixValue(back, backLength))
            = SubSeq(front, 1, frontLength) \o SubSeq(back, 1, backLength)
    PROOF
    <1>1. frontLength <= Len(front)
            BY SMT DEF SourceDefined, SourceLeftDefined, SourceRightDefined
    <1>2. backLength <= Len(back)
            BY SMT DEF SourceDefined, SourceLeftDefined, SourceRightDefined
    <1>3. SourcePrefixValue(front, frontLength) = SubSeq(front, 1, frontLength)
            BY PrefixPreservesSourceIndices, <1>1 DEF CompiledPrefixValue
    <1>4. SourcePrefixValue(back, backLength) = SubSeq(back, 1, backLength)
            BY PrefixPreservesSourceIndices, <1>2 DEF CompiledPrefixValue
    <1>5. SourcePrefixValue(front, frontLength) \in Seq(Int)
            BY IsASeq, <1>1, <1>3, SubSeqProperties
    <1>6. SourcePrefixValue(back, backLength) \in Seq(Int)
            BY IsASeq, <1>2, <1>4, SubSeqProperties
    <1>7. QED BY <1>3, <1>4, <1>5, <1>6,
            ConcatenationPreservesSourceIndices, SMT

THEOREM CompleteLabeledStepPreserved ==
    ASSUME front \in Seq(Int), back \in Seq(Int),
           frontLength \in Int, backLength \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (combine <=> SourceCombine)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY DefinedConcatenationValuePreserved, SMT
        DEF Init, SourceInit, combine, SourceCombine, SourceDefined,
            SourceLeftDefined, SourceRightDefined, Next, SourceNext,
            EmittedLabeled, SourceLabeled

THEOREM OrderedFailuresAndSelectedCheckPreserved ==
    ASSUME front \in Seq(Int), back \in Seq(Int),
           frontLength \in Int, backLength \in Int
    PROVE /\ (SourceLeftFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ (SourceRightFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0_1)
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0
                = <<frontLength, Len(front)>>
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0_1
                = <<backLength, Len(back)>>
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY SMT DEF SourceLeftFailure, SourceRightFailure,
        SourceLeftDefined, SourceRightDefined, SourceEvaluationOK,
        __SwiftTLASequenceIndexOutOfBoundsFailure0,
        __SwiftTLASequenceIndexOutOfBoundsFailure0_1,
        __SwiftTLASequenceIndexOutOfBoundsOperands0,
        __SwiftTLASequenceIndexOutOfBoundsOperands0_1,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

THEOREM InvalidLeftSuppressesRightFailure ==
    ASSUME front \in Seq(Int), back \in Seq(Int),
           frontLength \in Int, backLength \in Int,
           frontLength > Len(front)
    PROVE /\ __SwiftTLASequenceIndexOutOfBoundsFailure0
          /\ ~__SwiftTLASequenceIndexOutOfBoundsFailure0_1
          /\ ~combine
          /\ ~__SwiftTLAEvaluationOK
    BY SMT DEF combine,
        __SwiftTLASequenceIndexOutOfBoundsFailure0,
        __SwiftTLASequenceIndexOutOfBoundsFailure0_1,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

THEOREM InvalidRightAfterValidLeftReportsRight ==
    ASSUME front \in Seq(Int), back \in Seq(Int),
           frontLength \in Int, backLength \in Int,
           frontLength <= Len(front), backLength > Len(back)
    PROVE /\ ~__SwiftTLASequenceIndexOutOfBoundsFailure0
          /\ __SwiftTLASequenceIndexOutOfBoundsFailure0_1
          /\ ~combine
          /\ ~__SwiftTLAEvaluationOK
    BY SMT DEF combine,
        __SwiftTLASequenceIndexOutOfBoundsFailure0,
        __SwiftTLASequenceIndexOutOfBoundsFailure0_1,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

THEOREM EagerRightFailureWouldDisagree ==
    ASSUME front = <<1>>, back = <<2, 2>>,
           frontLength = 2, backLength = 3
    PROVE /\ ~__SwiftTLASequenceIndexOutOfBoundsFailure0_1
          /\ backLength > Len(back)
    BY InvalidLeftSuppressesRightFailure, SMT

==========================================================================
