---------------- MODULE FallibleSequenceLengthProof ----------------
EXTENDS TLAPS, SequencePrefixRule, SequenceLengthRule, FallibleSequenceLengthMachine

SourceInit == values = <<1>> /\ length \in 1..2 /\ result = 0
SourceDefined == length <= Len(values)
SourceMeasure ==
    IF SourceDefined
    THEN result' = SourceSequenceLength(SourceSequencePrefix(values, length))
         /\ UNCHANGED <<values, length>>
    ELSE FALSE
SourceNext == SourceMeasure
SourceLabeled(label) == label = "measure" /\ SourceMeasure
EmittedLabeled(label) == label = "measure" /\ measure
SourceFailure == ~SourceDefined
SourceEvaluationOK == ~SourceFailure

THEOREM DefinedValuePreserved ==
    ASSUME values \in Seq(Int), length \in Int, SourceDefined
    PROVE SourceSequenceLength(SourceSequencePrefix(values, length))
        = Len(SubSeq(values, 1, length))
    BY SequencePrefixValuePreserved, SequenceLengthIsDomainSize, IsASeq,
        SubSeqProperties, SMT DEF SourceDefined

THEOREM CompleteLabeledStepPreserved ==
    ASSUME values \in Seq(Int), length \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (measure <=> SourceMeasure)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY DefinedValuePreserved, SMT
        DEF Init, SourceInit, measure, SourceMeasure, SourceDefined,
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

THEOREM CompleteFallibleLengthSlice ==
    ASSUME values \in Seq(Int), length \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (measure <=> SourceMeasure)
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
