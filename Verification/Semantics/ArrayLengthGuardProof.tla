---------------- MODULE ArrayLengthGuardProof ----------------
EXTENDS TLAPS, SequenceTheorems, ArrayStepMachine

SourceInit == values = <<>>
SourceAppend == Len(values) < 2 /\ values' = values \o <<1>>
SourceNext == SourceAppend
SourceBounded == Len(values) <= 2
SourceLabeled(label) == label = "append" /\ SourceAppend
EmittedLabeled(label) == label = "append" /\ append

THEOREM CompleteArrayLengthStepPreserved ==
    ASSUME values \in Seq(Int), NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (append <=> SourceAppend)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
          /\ (bounded <=> SourceBounded)
    BY AppendIsConcat, SMT
        DEF Init, SourceInit, append, SourceAppend,
            Next, SourceNext, EmittedLabeled, SourceLabeled,
            bounded, SourceBounded

THEOREM InitialArrayStateHasBound ==
    Init => values \in Seq(Int) /\ SourceBounded
    BY SMT DEF Init, SourceBounded

THEOREM ArrayAppendPreservesBound ==
    ASSUME values \in Seq(Int), SourceBounded, append
    PROVE values' \in Seq(Int) /\ SourceBounded'
    BY AppendProperties, SMT
        DEF SourceBounded, append

THEOREM ArrayLengthControlsEnabledness ==
    ASSUME values \in Seq(Int)
    PROVE ENABLED append <=> Len(values) < 2
    BY AppendProperties, ExpandENABLED, SMT DEF append

WrongBoundAppend == Len(values) < 3 /\ values' = values \o <<1>>

THEOREM RelaxedBoundAddsAnInvalidEdge ==
    ASSUME values = <<1, 1>>
    PROVE ~ENABLED append /\ ENABLED WrongBoundAppend
    BY ExpandENABLED, SMT DEF append, WrongBoundAppend

=====================================================================
