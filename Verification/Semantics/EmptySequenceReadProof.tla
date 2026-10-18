---------------- MODULE EmptySequenceReadProof ----------------
EXTENDS TLAPS, EmptySequenceReadMachine

SourceNonempty(value) == Len(value) > 0
CompiledNonempty(value) == Len(value) > 0
NativeNonempty(value) == value # <<>>

THEOREM NonemptySequenceRule ==
    ASSUME NEW value \in Seq(Int)
    PROVE SourceNonempty(value) <=> NativeNonempty(value)
    BY SMT DEF SourceNonempty, NativeNonempty

SourceInit ==
    /\ sequence = <<>>
    /\ head = 0
    /\ tail = <<>>
SourceHead ==
    IF SourceNonempty(sequence)
    THEN head' = Head(sequence) /\ UNCHANGED <<sequence, tail>>
    ELSE FALSE
SourceTail ==
    IF SourceNonempty(sequence)
    THEN tail' = Tail(sequence) /\ UNCHANGED <<sequence, head>>
    ELSE FALSE
SourceNext == SourceHead \/ SourceTail
SourceHeadFailure == ~SourceNonempty(sequence)
SourceTailFailure == ~SourceNonempty(sequence)
SourceEvaluationOK == ~SourceHeadFailure /\ ~SourceTailFailure

CompiledHead ==
    IF CompiledNonempty(sequence)
    THEN head' = Head(sequence) /\ UNCHANGED <<sequence, tail>>
    ELSE FALSE
CompiledTail ==
    IF CompiledNonempty(sequence)
    THEN tail' = Tail(sequence) /\ UNCHANGED <<sequence, head>>
    ELSE FALSE
CompiledHeadFailure == ~CompiledNonempty(sequence)
CompiledTailFailure == ~CompiledNonempty(sequence)

SourceLabeledHead(label) == label = "readHead" /\ SourceHead
SourceLabeledTail(label) == label = "readTail" /\ SourceTail
EmittedLabeledHead(label) == label = "readHead" /\ readHead
EmittedLabeledTail(label) == label = "readTail" /\ readTail

THEOREM InitialStatesPreserved ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM LoweredActionsPreserveSource ==
    ASSUME sequence \in Seq(Int)
    PROVE /\ (SourceHead <=> CompiledHead)
          /\ (SourceTail <=> CompiledTail)
          /\ (SourceHeadFailure <=> CompiledHeadFailure)
          /\ (SourceTailFailure <=> CompiledTailFailure)
    PROOF
    <1>1. SourceHead <=> CompiledHead
        BY DEF SourceHead, CompiledHead, SourceNonempty, CompiledNonempty
    <1>2. SourceTail <=> CompiledTail
        BY DEF SourceTail, CompiledTail, SourceNonempty, CompiledNonempty
    <1>3. SourceHeadFailure <=> CompiledHeadFailure
        BY DEF SourceHeadFailure, CompiledHeadFailure,
            SourceNonempty, CompiledNonempty
    <1>4. SourceTailFailure <=> CompiledTailFailure
        BY DEF SourceTailFailure, CompiledTailFailure,
            SourceNonempty, CompiledNonempty
    <1>5. QED BY <1>1, <1>2, <1>3, <1>4

THEOREM EmittedActionsPreserveLowering ==
    ASSUME sequence \in Seq(Int)
    PROVE /\ (CompiledHead <=> readHead)
          /\ (CompiledTail <=> readTail)
          /\ (CompiledHeadFailure
                <=> __SwiftTLAEmptySequenceFailure0)
          /\ (CompiledTailFailure
                <=> __SwiftTLAEmptySequenceFailure1)
          /\ (CompiledHeadFailure <=> __SwiftTLAAnyEvaluationFailure0)
          /\ (CompiledTailFailure <=> __SwiftTLAAnyEvaluationFailure1)
    BY SMT DEF CompiledHead, CompiledTail, readHead, readTail,
        CompiledHeadFailure, CompiledTailFailure, CompiledNonempty,
        __SwiftTLAEmptySequenceFailure0,
        __SwiftTLAEmptySequenceFailure1,
        __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAAnyEvaluationFailure1

THEOREM CompleteHeadTailSlice ==
    ASSUME sequence \in Seq(Int), NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (SourceLabeledHead(label) <=> EmittedLabeledHead(label))
          /\ (SourceLabeledTail(label) <=> EmittedLabeledTail(label))
          /\ (SourceNext <=> Next)
          /\ (SourceHeadFailure
                <=> __SwiftTLAEmptySequenceFailure0)
          /\ (SourceTailFailure
                <=> __SwiftTLAEmptySequenceFailure1)
          /\ (SourceHeadFailure <=> __SwiftTLAAnyEvaluationFailure0)
          /\ (SourceTailFailure <=> __SwiftTLAAnyEvaluationFailure1)
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY InitialStatesPreserved, LoweredActionsPreserveSource,
        EmittedActionsPreserveLowering, SMT
        DEF SourceLabeledHead, EmittedLabeledHead,
            SourceLabeledTail, EmittedLabeledTail,
            SourceNext, Next, SourceEvaluationOK,
            __SwiftTLAAnyEvaluationFailure0,
            __SwiftTLAAnyEvaluationFailure1,
            __SwiftTLAEvaluationOK

THEOREM EmptyInitialSequenceHasFailuresAndNoSteps ==
    ASSUME sequence = <<>>
    PROVE /\ ~readHead
          /\ ~readTail
          /\ __SwiftTLAEmptySequenceFailure0
          /\ __SwiftTLAEmptySequenceFailure1
          /\ ~__SwiftTLAEvaluationOK
    BY SMT DEF readHead, readTail,
        __SwiftTLAEmptySequenceFailure0,
        __SwiftTLAEmptySequenceFailure1,
        __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAAnyEvaluationFailure1,
        __SwiftTLAEvaluationOK

THEOREM OmittingFailureCheckWouldDisagree ==
    ASSUME sequence = <<>>
    PROVE TRUE # __SwiftTLAEvaluationOK
    BY EmptyInitialSequenceHasFailuresAndNoSteps

================================================================
