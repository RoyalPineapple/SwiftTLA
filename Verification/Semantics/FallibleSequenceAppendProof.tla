---------------- MODULE FallibleSequenceAppendProof ----------------
EXTENDS TLAPS, SequencePrefixRule, FallibleSequenceAppendMachine

SourceAppend(value, element) ==
    [index \in 1..(Len(value) + 1) |->
        IF index <= Len(value) THEN value[index] ELSE element]

SourceInit == values = <<1>> /\ length \in 1..2
SourceDefined == length <= Len(values)
SourceStep ==
    IF SourceDefined
    THEN values' = SourceAppend(SourceSequencePrefix(values, length), 3)
         /\ UNCHANGED length
    ELSE FALSE
SourceNext == SourceStep
SourceLabeled(label) == label = "append" /\ SourceStep
EmittedLabeled(label) == label = "append" /\ append
SourceFailure == ~SourceDefined
SourceEvaluationOK == ~SourceFailure

THEOREM AppendValuePreserved ==
    ASSUME NEW value \in Seq(Int), NEW element \in Int
    PROVE SourceAppend(value, element) = Append(value, element)
    BY SMT DEF SourceAppend

THEOREM DefinedValuePreserved ==
    ASSUME values \in Seq(Int), length \in Int, SourceDefined
    PROVE SourceAppend(SourceSequencePrefix(values, length), 3)
        = Append(SubSeq(values, 1, length), 3)
    BY SequencePrefixValuePreserved, AppendValuePreserved, IsASeq,
        SubSeqProperties, SMT DEF SourceDefined

THEOREM CompleteLabeledStepPreserved ==
    ASSUME values \in Seq(Int), length \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (append <=> SourceStep)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY DefinedValuePreserved, SMT
        DEF Init, SourceInit, append, SourceStep, SourceDefined,
            Next, SourceNext, EmittedLabeled, SourceLabeled

THEOREM FailureAndSelectedCheckPreserved ==
    ASSUME values \in Seq(Int), length \in Int
    PROVE /\ (SourceFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0
                = <<length, Len(values)>>
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY SMT DEF SourceFailure, SourceDefined, SourceEvaluationOK,
        __SwiftTLASequenceIndexOutOfBoundsFailure0,
        __SwiftTLASequenceIndexOutOfBoundsOperands0,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

THEOREM CompleteFallibleAppendSlice ==
    ASSUME values \in Seq(Int), length \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (append <=> SourceStep)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
          /\ (Next <=> SourceNext)
          /\ (SourceFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0
                = <<length, Len(values)>>
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY CompleteLabeledStepPreserved, FailureAndSelectedCheckPreserved

WrongAlwaysEvaluationOK == TRUE

THEOREM MissingFailureReportWouldDisagree ==
    ASSUME values = <<1>>, length = 2
    PROVE ~SourceEvaluationOK /\ WrongAlwaysEvaluationOK
    BY SMT DEF SourceEvaluationOK, SourceFailure,
        SourceDefined, WrongAlwaysEvaluationOK

=======================================================================
