---------------- MODULE FallibleSequenceAppendProof ----------------
EXTENDS TLAPS, SequenceTheorems, FallibleSequenceAppendMachine

SourcePrefix(value, count) ==
    IF count < 1 THEN <<>> ELSE [index \in 1..count |-> value[index]]
SourceAppend(value, element) ==
    [index \in 1..(Len(value) + 1) |->
        IF index <= Len(value) THEN value[index] ELSE element]

SourceInit == values = <<1>> /\ length \in 1..2
SourceDefined == length <= Len(values)
SourceStep ==
    IF SourceDefined
    THEN values' = SourceAppend(SourcePrefix(values, length), 3)
         /\ UNCHANGED length
    ELSE FALSE
SourceNext == SourceStep
SourceLabeled(label) == label = "append" /\ SourceStep
EmittedLabeled(label) == label = "append" /\ append
SourceFailure == ~SourceDefined
SourceEvaluationOK == ~SourceFailure

THEOREM PrefixValuePreserved ==
    ASSUME NEW value \in Seq(Int), NEW count \in Int,
           count <= Len(value)
    PROVE SourcePrefix(value, count) = SubSeq(value, 1, count)
    PROOF
    <1>1. CASE count < 1
        <2>1. SourcePrefix(value, count) = <<>>
            BY <1>1 DEF SourcePrefix
        <2>2. SubSeq(value, 1, count) = <<>>
            BY <1>1, SubSeqEmpty, SMT
        <2>3. QED BY <2>1, <2>2
    <1>2. CASE count >= 1
        <2>1. count \in 0..Len(value) BY <1>2, SMT
        <2>2. SubSeq(value, 1, count) = Restrict(value, 1..count)
            BY <2>1, SubSeqRestrict
        <2>3. SourcePrefix(value, count) = Restrict(value, 1..count)
            BY <1>2, SMT DEF SourcePrefix, Restrict
        <2>4. QED BY <2>2, <2>3
    <1>3. QED BY <1>1, <1>2, SMT

THEOREM AppendValuePreserved ==
    ASSUME NEW value \in Seq(Int), NEW element \in Int
    PROVE SourceAppend(value, element) = Append(value, element)
    BY SMT DEF SourceAppend

THEOREM DefinedValuePreserved ==
    ASSUME values \in Seq(Int), length \in Int, SourceDefined
    PROVE SourceAppend(SourcePrefix(values, length), 3)
        = Append(SubSeq(values, 1, length), 3)
    BY PrefixValuePreserved, AppendValuePreserved, IsASeq,
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
