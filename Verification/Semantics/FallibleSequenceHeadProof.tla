---------------- MODULE FallibleSequenceHeadProof ----------------
EXTENDS TLAPS, SequencePrefixRule, SequenceHeadRule,
        FallibleSequenceHeadMachine

SourceInit == values = <<1>> /\ length \in 0..2 /\ result = 0
SourcePrefixDefined == length <= Len(values)
SourceHeadDefined ==
    SourceSequenceHasHead(SourceSequencePrefix(values, length))
SourceDefined == SourcePrefixDefined /\ SourceHeadDefined
SourceReadHead ==
    IF SourceDefined
    THEN result' = SourceSequenceHead(SourceSequencePrefix(values, length))
         /\ UNCHANGED <<values, length>>
    ELSE FALSE
SourceNext == SourceReadHead
SourceLabeled(label) == label = "readHead" /\ SourceReadHead
EmittedLabeled(label) == label = "readHead" /\ readHead
SourcePrefixFailure == ~SourcePrefixDefined
SourceEmptyFailure ==
    IF SourcePrefixDefined THEN ~SourceHeadDefined ELSE FALSE
SourceEvaluationOK == ~(SourcePrefixFailure \/ SourceEmptyFailure)

THEOREM PrefixHeadDefinedPreserved ==
    ASSUME values \in Seq(Int), length \in Int, SourcePrefixDefined
    PROVE SourceHeadDefined <=> Len(SubSeq(values, 1, length)) > 0
    BY SequencePrefixValuePreserved, HeadDefinedByLength,
        SubSeqProperties, IsASeq, SMT
        DEF SourceHeadDefined, SourcePrefixDefined

THEOREM DefinedHeadValuePreserved ==
    ASSUME values \in Seq(Int), length \in Int, SourceDefined
    PROVE SourceSequenceHead(SourceSequencePrefix(values, length))
        = Head(SubSeq(values, 1, length))
    BY SequencePrefixValuePreserved, HeadValuePreserved,
        SubSeqProperties, IsASeq, SMT
        DEF SourceDefined, SourcePrefixDefined, SourceHeadDefined

THEOREM CompleteLabeledStepPreserved ==
    ASSUME values \in Seq(Int), length \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (readHead <=> SourceReadHead)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
    BY PrefixHeadDefinedPreserved, DefinedHeadValuePreserved, SMT
        DEF Init, SourceInit, readHead, SourceReadHead, SourceDefined,
            SourcePrefixDefined, SourceHeadDefined, Next, SourceNext,
            EmittedLabeled, SourceLabeled

THEOREM OrderedFailuresAndSelectedCheckPreserved ==
    ASSUME values \in Seq(Int), length \in Int
    PROVE /\ (SourcePrefixFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0
                = <<length, Len(values)>>
          /\ (SourceEmptyFailure <=> __SwiftTLAEmptySequenceFailure0)
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY PrefixHeadDefinedPreserved, SMT
        DEF SourcePrefixFailure, SourcePrefixDefined,
            SourceEmptyFailure, SourceHeadDefined, SourceEvaluationOK,
            __SwiftTLASequenceIndexOutOfBoundsFailure0,
            __SwiftTLASequenceIndexOutOfBoundsOperands0,
            __SwiftTLAEmptySequenceFailure0,
            __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

THEOREM CompleteFallibleHeadSlice ==
    ASSUME values \in Seq(Int), length \in Int, NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (readHead <=> SourceReadHead)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
          /\ (Next <=> SourceNext)
          /\ (SourcePrefixFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0
                = <<length, Len(values)>>
          /\ (SourceEmptyFailure <=> __SwiftTLAEmptySequenceFailure0)
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY CompleteLabeledStepPreserved, OrderedFailuresAndSelectedCheckPreserved

WrongAlwaysEvaluationOK == TRUE

THEOREM EmptyPrefixRejectsUnconditionalSuccess ==
    ASSUME values = <<1>>, length = 0
    PROVE SourceEmptyFailure /\ ~SourceEvaluationOK
        /\ WrongAlwaysEvaluationOK
    BY SMT DEF SourceEmptyFailure, SourceEvaluationOK,
        SourcePrefixFailure, SourcePrefixDefined, SourceHeadDefined,
        SourceSequenceHasHead, SourceSequencePrefix,
        WrongAlwaysEvaluationOK

THEOREM InvalidPrefixPrecedesEmptyFailure ==
    ASSUME values = <<1>>, length = 2
    PROVE SourcePrefixFailure /\ ~SourceEmptyFailure
        /\ ~SourceEvaluationOK
    BY SMT DEF SourcePrefixFailure, SourcePrefixDefined,
        SourceEmptyFailure, SourceEvaluationOK

===================================================================
