---------------- MODULE SequenceEditPreservationProof ----------------
EXTENDS TLAPS, SequencePrefixRule, SequenceEditBoundsMachine

SourceRemoveDefined(value, index) == index \in 1..Len(value)
CompiledRemoveDefined(value, index) == index \in DOMAIN value
SourcePrefixDefined(value, length) == length <= Len(value)

SourceRemoveValue(value, index) ==
    [position \in 1..(Len(value) - 1) |->
        IF position < index THEN value[position] ELSE value[position + 1]]
CompiledRemoveValue(value, index) ==
    SubSeq(value, 1, index - 1) \o SubSeq(value, index + 1, Len(value))
THEOREM RemoveDomainPreserved ==
    ASSUME NEW value \in Seq(Int), NEW index \in Int
    PROVE SourceRemoveDefined(value, index)
        <=> CompiledRemoveDefined(value, index)
    BY SMT DEF SourceRemoveDefined, CompiledRemoveDefined

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
    THEN row' = SourceSequencePrefix(row, position) /\ UNCHANGED position
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
    BY SequencePrefixValuePreserved, SMT
        DEF SourcePrefix, prefix, SourcePrefixDefined

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
