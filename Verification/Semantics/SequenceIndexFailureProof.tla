---------------- MODULE SequenceIndexFailureProof ----------------
EXTENDS TLAPS, ArrayReadOutsideDomainMachine

SourceIndexDefined(value, index) ==
    index \in 1..Len(value)
CompiledIndexDefined(value, index) ==
    1 <= index /\ index <= Len(value)
RenderedIndexDefined(value, index) ==
    index \in DOMAIN value
SourceIndexFailure(value, index) ==
    IF SourceIndexDefined(value, index)
    THEN {}
    ELSE {<<"indexOutOfBounds", index, Len(value)>>}
RenderedIndexFailure(value, index) ==
    IF RenderedIndexDefined(value, index)
    THEN {}
    ELSE {<<"indexOutOfBounds", index, Len(value)>>}

THEOREM SourceLoweringPreservesIndexBounds ==
    ASSUME NEW value \in Seq(Int), NEW index \in Int
    PROVE SourceIndexDefined(value, index)
        <=> CompiledIndexDefined(value, index)
    BY SMT DEF SourceIndexDefined, CompiledIndexDefined

THEOREM SequenceDomainMatchesCompiledBounds ==
    ASSUME NEW value \in Seq(Int), NEW index \in Int
    PROVE CompiledIndexDefined(value, index)
        <=> RenderedIndexDefined(value, index)
    BY SMT DEF CompiledIndexDefined, RenderedIndexDefined

THEOREM SequenceFailureRule ==
    ASSUME NEW value \in Seq(Int), NEW index \in Int
    PROVE SourceIndexFailure(value, index)
        = RenderedIndexFailure(value, index)
    BY SourceLoweringPreservesIndexBounds,
        SequenceDomainMatchesCompiledBounds, SMT
        DEF SourceIndexFailure, RenderedIndexFailure,
            SourceIndexDefined, CompiledIndexDefined,
            RenderedIndexDefined

SourceInit ==
    /\ sequence = <<>>
    /\ result = 0
SourceRead ==
    IF SourceIndexDefined(sequence, 1)
    THEN result' = sequence[1] /\ UNCHANGED sequence
    ELSE FALSE
CompiledRead ==
    IF CompiledIndexDefined(sequence, 1)
    THEN result' = sequence[1] /\ UNCHANGED sequence
    ELSE FALSE
SourceFailure ==
    ~SourceIndexDefined(sequence, 1)
SourceFailureOperands == <<1, Len(sequence)>>
SourceEvaluationOK == ~SourceFailure
SourceLabeledRead(label) == label = "read" /\ SourceRead
EmittedLabeledRead(label) == label = "read" /\ read

THEOREM InitialStatesPreserved ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM LoweredReadPreservesSource ==
    ASSUME sequence \in Seq(Int)
    PROVE SourceRead <=> CompiledRead
    BY SourceLoweringPreservesIndexBounds, SMT
        DEF SourceRead, CompiledRead, SourceIndexDefined,
            CompiledIndexDefined

THEOREM EmittedReadPreservesLowering ==
    ASSUME sequence \in Seq(Int)
    PROVE CompiledRead <=> read
    BY SequenceDomainMatchesCompiledBounds, SMT
        DEF CompiledRead, read, CompiledIndexDefined,
            RenderedIndexDefined

THEOREM FailureAndSelectedCheckPreserved ==
    ASSUME sequence \in Seq(Int)
    PROVE /\ (SourceFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ SourceFailureOperands
                = __SwiftTLASequenceIndexOutOfBoundsOperands0
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY SourceLoweringPreservesIndexBounds,
        SequenceDomainMatchesCompiledBounds, SMT
        DEF SourceFailure, SourceFailureOperands, SourceEvaluationOK,
            SourceIndexDefined, CompiledIndexDefined,
            RenderedIndexDefined,
            __SwiftTLASequenceIndexOutOfBoundsFailure0,
            __SwiftTLASequenceIndexOutOfBoundsOperands0,
            __SwiftTLAEvaluationOK

THEOREM CompleteSequenceReadSlice ==
    ASSUME sequence \in Seq(Int), NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (SourceLabeledRead(label) <=> EmittedLabeledRead(label))
          /\ (SourceFailure
                <=> __SwiftTLASequenceIndexOutOfBoundsFailure0)
          /\ SourceFailureOperands
                = __SwiftTLASequenceIndexOutOfBoundsOperands0
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY InitialStatesPreserved, LoweredReadPreservesSource,
        EmittedReadPreservesLowering,
        FailureAndSelectedCheckPreserved, SMT
        DEF SourceLabeledRead, EmittedLabeledRead

THEOREM EmptySequenceReportsFailureWithoutSuccessor ==
    ASSUME sequence = <<>>
    PROVE /\ ~SourceRead
          /\ ~read
          /\ __SwiftTLASequenceIndexOutOfBoundsFailure0
          /\ __SwiftTLASequenceIndexOutOfBoundsOperands0 = <<1, 0>>
          /\ ~__SwiftTLAEvaluationOK
    BY LoweredReadPreservesSource, EmittedReadPreservesLowering,
        FailureAndSelectedCheckPreserved,
        SourceLoweringPreservesIndexBounds,
        SequenceDomainMatchesCompiledBounds, SMT
        DEF SourceRead, SourceIndexDefined, SourceFailure,
            SourceFailureOperands, SourceEvaluationOK

THEOREM OmittingFailureCheckWouldDisagree ==
    ASSUME sequence = <<>>
    PROVE TRUE # __SwiftTLAEvaluationOK
    BY EmptySequenceReportsFailureWithoutSuccessor

=================================================================
