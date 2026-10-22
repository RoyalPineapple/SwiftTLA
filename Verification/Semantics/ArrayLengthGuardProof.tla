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

THEOREM SourceAppendEnabledWhenBelowBound ==
    ASSUME values \in Seq(Int), Len(values) < 2
    PROVE ENABLED SourceAppend
    PROOF
    <1>1. \E next : Len(values) < 2 /\ next = values \o <<1>>
        PROOF
        <2>1. WITNESS values \o <<1>>
        <2>. QED BY SMT
    <1>. QED BY <1>1, ExpandENABLED DEF SourceAppend

THEOREM ArrayLengthControlsEnabledness ==
    ASSUME values \in Seq(Int)
    PROVE ENABLED append <=> Len(values) < 2
    PROOF
    <1>1. append <=> SourceAppend
        BY AppendIsConcat, SMT DEF append, SourceAppend
    <1>2. ENABLED SourceAppend <=> Len(values) < 2
        PROOF
        <2>1. ENABLED SourceAppend => Len(values) < 2
            BY ExpandENABLED, SMT DEF SourceAppend
        <2>2. Len(values) < 2 => ENABLED SourceAppend
            BY SourceAppendEnabledWhenBelowBound, SMT
        <2>. QED BY <2>1, <2>2
    <1>3. ENABLED append <=> ENABLED SourceAppend
        BY <1>1, ExpandENABLED, SMT
        DEF append, SourceAppend
    <1>. QED BY <1>2, <1>3

WrongBoundAppend == Len(values) < 3 /\ values' = values \o <<1>>

THEOREM RelaxedBoundAddsAnInvalidEdge ==
    ASSUME values = <<1, 1>>
    PROVE ~ENABLED append /\ ENABLED WrongBoundAppend
    BY ExpandENABLED, SMT DEF append, WrongBoundAppend

=====================================================================
