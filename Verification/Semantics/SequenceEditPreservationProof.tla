---------------- MODULE SequenceEditPreservationProof ----------------
EXTENDS TLAPS, SequenceTheorems, SequenceEditBoundsMachine

SourceRemoveDefined(value, index) == index \in 1..Len(value)
CompiledRemoveDefined(value, index) == index \in DOMAIN value
SourcePrefixDefined(value, length) == length <= Len(value)

SourceRemoveValue(value, index) ==
    [position \in 1..(Len(value) - 1) |->
        IF position < index THEN value[position] ELSE value[position + 1]]
CompiledRemoveValue(value, index) ==
    SubSeq(value, 1, index - 1) \o SubSeq(value, index + 1, Len(value))
SourcePrefixValue(value, length) ==
    [position \in 1..length |-> value[position]]
CompiledPrefixValue(value, length) == SubSeq(value, 1, length)

THEOREM RemoveDomainPreserved ==
    ASSUME NEW value \in Seq(Int), NEW index \in Int
    PROVE SourceRemoveDefined(value, index)
        <=> CompiledRemoveDefined(value, index)
    BY SMT DEF SourceRemoveDefined, CompiledRemoveDefined

THEOREM PrefixValuePreserved ==
    ASSUME NEW value \in Seq(Int), NEW length \in Int,
           SourcePrefixDefined(value, length)
    PROVE SourcePrefixValue(value, length) = CompiledPrefixValue(value, length)
    PROOF
    <1>1. CASE length < 1
        <2>1. SourcePrefixValue(value, length) = <<>>
            BY <1>1, SMT DEF SourcePrefixValue
        <2>2. CompiledPrefixValue(value, length) = <<>>
            BY <1>1, SubSeqEmpty, SMT DEF CompiledPrefixValue
        <2>3. QED BY <2>1, <2>2
    <1>2. CASE length >= 1
        <2>1. length \in 0..Len(value)
            BY <1>2, SMT DEF SourcePrefixDefined
        <2>2. CompiledPrefixValue(value, length)
                = Restrict(value, 1..length)
            BY SubSeqRestrict, <2>1 DEF CompiledPrefixValue
        <2>3. SourcePrefixValue(value, length)
                = Restrict(value, 1..length)
            BY SMT DEF SourcePrefixValue, Restrict
        <2>4. QED BY <2>2, <2>3
    <1>3. QED BY <1>1, <1>2, SMT

THEOREM RemoveValuePreserved ==
    ASSUME NEW value \in Seq(Int), NEW index \in Int,
           SourceRemoveDefined(value, index)
    PROVE SourceRemoveValue(value, index) = CompiledRemoveValue(value, index)
    BY SubSeqProperties, ConcatProperties, SeqEqual, SMT
        DEF SourceRemoveValue, CompiledRemoveValue,
            SourceRemoveDefined

SourceInit == row = <<4, 5>> /\ position \in 2..3
SourceRemove ==
    IF SourceRemoveDefined(row, position)
    THEN row' = SourceRemoveValue(row, position) /\ UNCHANGED position
    ELSE FALSE
SourcePrefix ==
    IF SourcePrefixDefined(row, position)
    THEN row' = SourcePrefixValue(row, position) /\ UNCHANGED position
    ELSE FALSE
SourceNext == SourceRemove \/ SourcePrefix
SourceRemoveFailure == ~SourceRemoveDefined(row, position)
SourcePrefixFailure == ~SourcePrefixDefined(row, position)
SourceEvaluationOK == ~SourceRemoveFailure /\ ~SourcePrefixFailure
SourceLabeledRemove(label) == label = "remove" /\ SourceRemove
SourceLabeledPrefix(label) == label = "prefix" /\ SourcePrefix
EmittedLabeledRemove(label) == label = "remove" /\ remove
EmittedLabeledPrefix(label) == label = "prefix" /\ prefix

THEOREM InitialStatesPreserved ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM RemoveActionPreserved ==
    ASSUME row \in Seq(Int), position \in Int
    PROVE SourceRemove <=> remove
    BY RemoveDomainPreserved, RemoveValuePreserved, SMT
        DEF SourceRemove, remove, SourceRemoveDefined,
            CompiledRemoveDefined, SourceRemoveValue,
            CompiledRemoveValue

THEOREM PrefixActionPreserved ==
    ASSUME row \in Seq(Int), position \in Int
    PROVE SourcePrefix <=> prefix
    BY PrefixValuePreserved, SMT
        DEF SourcePrefix, prefix, SourcePrefixDefined,
            SourcePrefixValue, CompiledPrefixValue

THEOREM FailuresAndSelectedCheckPreserved ==
    ASSUME row \in Seq(Int), position \in Int
    PROVE /\ (SourceRemoveFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ (SourcePrefixFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure1)
          /\ (SourceRemoveFailure <=> __SwiftTLAAnyEvaluationFailure0)
          /\ (SourcePrefixFailure <=> __SwiftTLAAnyEvaluationFailure1)
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0
                = <<position, Len(row)>>
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands1
                = <<position, Len(row)>>
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY RemoveDomainPreserved, SMT
        DEF SourceRemoveFailure, SourcePrefixFailure,
            SourceRemoveDefined, SourcePrefixDefined,
            SourceEvaluationOK,
            __SwiftTLASequenceIndexOutOfBoundsFailure0,
            __SwiftTLASequenceIndexOutOfBoundsFailure1,
            __SwiftTLAAnyEvaluationFailure0,
            __SwiftTLAAnyEvaluationFailure1,
            __SwiftTLASequenceIndexOutOfBoundsOperands0,
            __SwiftTLASequenceIndexOutOfBoundsOperands1,
            __SwiftTLAEvaluationOK

THEOREM CompleteSequenceEditSlice ==
    ASSUME row \in Seq(Int), position \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (SourceLabeledRemove(label) <=> EmittedLabeledRemove(label))
          /\ (SourceLabeledPrefix(label) <=> EmittedLabeledPrefix(label))
          /\ (SourceNext <=> Next)
          /\ (SourceRemoveFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ (SourcePrefixFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure1)
          /\ (SourceRemoveFailure <=> __SwiftTLAAnyEvaluationFailure0)
          /\ (SourcePrefixFailure <=> __SwiftTLAAnyEvaluationFailure1)
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY InitialStatesPreserved, RemoveActionPreserved,
        PrefixActionPreserved, FailuresAndSelectedCheckPreserved,
        SMT DEF SourceLabeledRemove, EmittedLabeledRemove,
            SourceLabeledPrefix, EmittedLabeledPrefix,
            SourceNext, Next

THEOREM InvalidInitialPositionReportsBothFailures ==
    ASSUME row = <<4, 5>>, position = 3
    PROVE /\ ~remove
          /\ ~prefix
          /\ __SwiftTLASequenceIndexOutOfBoundsFailure0
          /\ __SwiftTLASequenceIndexOutOfBoundsFailure1
          /\ ~__SwiftTLAEvaluationOK
    BY SMT DEF remove, prefix,
        __SwiftTLASequenceIndexOutOfBoundsFailure0,
        __SwiftTLASequenceIndexOutOfBoundsFailure1,
        __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAAnyEvaluationFailure1,
        __SwiftTLAEvaluationOK

THEOREM OmittingFailureCheckWouldDisagree ==
    ASSUME row = <<4, 5>>, position = 3
    PROVE TRUE # __SwiftTLAEvaluationOK
    BY InvalidInitialPositionReportsBothFailures

=================================================================
