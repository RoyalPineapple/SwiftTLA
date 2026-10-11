------------------- MODULE CheckedExecutionOverflowProof -------------------
EXTENDS TLAPS, CheckedExecutionOverflow

SwiftIntMin == -9223372036854775808
SwiftIntMax == 9223372036854775807
WithinSwiftInt(value) == SwiftIntMin <= value /\ value <= SwiftIntMax

SourceInit == pc = "advance" /\ count = SwiftIntMax
SourceStep ==
    /\ pc = "advance"
    /\ WithinSwiftInt(count + 1)
    /\ count' = count + 1
    /\ pc' = "Done"
SourceTerminating ==
    /\ pc = "Done"
    /\ UNCHANGED <<pc, count>>
SourceNext == SourceStep \/ SourceTerminating
SourceLabeledMachineStep(label) == label = "advance" /\ SourceStep
EmittedLabeledMachineStep(label) == label = "advance" /\ advance
SourceFailure ==
    /\ pc = "advance"
    /\ ~WithinSwiftInt(count + 1)
SourceEvaluationOK == ~SourceFailure
SourceFailures ==
    IF SourceFailure
    THEN {<<pc, count, "advance", "addition", <<count, 1>>>>}
    ELSE {}
EmittedFailures ==
    IF __SwiftTLAOverflowFailure0
    THEN {<<pc, count, "advance", __SwiftTLAOverflowOperation0,
            __SwiftTLAOverflowOperands0>>}
    ELSE {}

THEOREM EmittedInitMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit, SwiftIntMax

THEOREM EmittedStepMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count)
    PROVE advance <=> SourceStep
    BY SMT DEF advance, SourceStep, WithinSwiftInt,
        SwiftIntMin, SwiftIntMax

THEOREM EmittedTerminatingMatchesSource ==
    Terminating <=> SourceTerminating
    BY SMT DEF Terminating, SourceTerminating

THEOREM EmittedNextMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count)
    PROVE Next <=> SourceNext
    BY EmittedStepMatchesSource, EmittedTerminatingMatchesSource
        DEF Next, SourceNext

THEOREM EmittedLabeledMachineStepMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count), NEW label
    PROVE EmittedLabeledMachineStep(label) <=> SourceLabeledMachineStep(label)
    BY EmittedStepMatchesSource, SMT
        DEF EmittedLabeledMachineStep, SourceLabeledMachineStep

THEOREM EmittedFailureMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count)
    PROVE /\ (__SwiftTLAOverflowFailure0 <=> SourceFailure)
          /\ __SwiftTLAOverflowOperands0 = <<count, 1>>
          /\ __SwiftTLAOverflowOperation0 = "addition"
    BY SMT DEF __SwiftTLAOverflowFailure0,
        __SwiftTLAOverflowOperands0, __SwiftTLAOverflowOperation0,
        SourceFailure,
        WithinSwiftInt, SwiftIntMin, SwiftIntMax

THEOREM EmittedFailureRecordMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count)
    PROVE EmittedFailures = SourceFailures
    BY EmittedFailureMatchesSource, SMT
        DEF EmittedFailures, SourceFailures

THEOREM EmittedEvaluationCheckMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count)
    PROVE __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedFailureMatchesSource, SMT
        DEF __SwiftTLAEvaluationOK, SourceEvaluationOK

THEOREM InitialStateHasFailureAndNoStep ==
    Init =>
        /\ ~Next
        /\ __SwiftTLAOverflowFailure0
        /\ ~__SwiftTLAEvaluationOK
        /\ __SwiftTLAOverflowOperands0 = <<SwiftIntMax, 1>>
        /\ __SwiftTLAOverflowOperation0 = "addition"
    BY EmittedInitMatchesSource, EmittedNextMatchesSource,
        EmittedFailureMatchesSource, EmittedEvaluationCheckMatchesSource, SMT
        DEF SourceInit, SourceNext, SourceStep,
            SourceTerminating, SourceFailure, SourceEvaluationOK,
            WithinSwiftInt, SwiftIntMax, SwiftIntMin

THEOREM UncheckedAdditionNegativeControl ==
    Init => \E result \in Int :
        result = count + 1 /\ ~WithinSwiftInt(result)
    BY SMT DEF Init, WithinSwiftInt, SwiftIntMax, SwiftIntMin

=============================================================================
