-------------------- MODULE CheckedGuardOverflowProof --------------------
EXTENDS TLAPS, CheckedGuardOverflow

SwiftIntMin == ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)
SwiftIntMax == ((9 * 1000000000 + 223372036) * 1000000000 + 854775807)
WithinSwiftInt(value) == SwiftIntMin <= value /\ value <= SwiftIntMax
EmittedDefined ==
    IF count >= -1000000000 /\ count <= 1000000000
       /\ 1 >= -1000000000 /\ 1 <= 1000000000
    THEN TRUE
    ELSE IF 1 > 0 THEN count <= SwiftIntMax - 1
    ELSE IF 1 < 0 THEN count >= SwiftIntMin - 1
    ELSE TRUE

SourceInit == pc = "advance" /\ count \in {SwiftIntMax, 1}
SourceAdvance ==
    /\ pc = "advance"
    /\ WithinSwiftInt(count + 1)
    /\ count + 1 > 0
    /\ count' = 0
    /\ pc' = "Done"
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, count>>
SourceNext == SourceAdvance \/ SourceTerminating
SourceFailure == pc = "advance" /\ ~WithinSwiftInt(count + 1)
SourceEvaluationOK == ~SourceFailure
StateDomain == pc \in {"advance", "Done"} /\ count \in Int /\ WithinSwiftInt(count)
SourceLabeled(label) ==
    \/ label = "advance" /\ SourceAdvance
    \/ label = "Terminating" /\ SourceTerminating
EmittedLabeled(label) ==
    \/ label = "advance" /\ advance
    \/ label = "Terminating" /\ Terminating

THEOREM EmittedGuardDefinednessMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count)
    PROVE EmittedDefined <=> WithinSwiftInt(count + 1)
    BY SMT DEF EmittedDefined, WithinSwiftInt,
        SwiftIntMin, SwiftIntMax

THEOREM InitialStatesSatisfyDomain ==
    Init => StateDomain
    BY SMT DEF Init, StateDomain, WithinSwiftInt,
        SwiftIntMin, SwiftIntMax

THEOREM CompleteNextPreservesDomain ==
    ASSUME StateDomain, Next
    PROVE StateDomain'
    BY EmittedGuardDefinednessMatchesSource, SMT
        DEF StateDomain, Next, advance, Terminating,
            EmittedDefined, WithinSwiftInt, SwiftIntMin, SwiftIntMax

THEOREM CompleteEmittedGuardMatchesSource ==
    ASSUME count \in Int, WithinSwiftInt(count), NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (Next <=> SourceNext)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
          /\ (__SwiftTLAOverflowFailure0 <=> SourceFailure)
          /\ (__SwiftTLAAnyEvaluationFailure0 <=> SourceFailure)
          /\ (__SwiftTLAEvaluationOK <=> SourceEvaluationOK)
          /\ __SwiftTLAOverflowOperation0 = "addition"
          /\ __SwiftTLAOverflowOperands0 = <<count, 1>>
    BY EmittedGuardDefinednessMatchesSource, SMT
        DEF Init, SourceInit, Next, SourceNext,
            advance, SourceAdvance, Terminating, SourceTerminating,
            EmittedLabeled, SourceLabeled, __SwiftTLAOverflowFailure0,
            __SwiftTLAAnyEvaluationFailure0,
            SourceFailure, __SwiftTLAEvaluationOK, SourceEvaluationOK,
            __SwiftTLAOverflowOperation0, __SwiftTLAOverflowOperands0,
            WithinSwiftInt, EmittedDefined, SwiftIntMin, SwiftIntMax

WrongUnguardedAdvance ==
    pc = "advance" /\ count + 1 > 0 /\ count' = 0 /\ pc' = "Done"

THEOREM OverflowStateRejectsUnguardedAdvance ==
    ASSUME pc = "advance", count = SwiftIntMax
    PROVE /\ ~ENABLED advance
          /\ __SwiftTLAOverflowFailure0
          /\ ENABLED WrongUnguardedAdvance
    BY EmittedGuardDefinednessMatchesSource, ExpandENABLED, SMT
        DEF advance, WrongUnguardedAdvance,
            __SwiftTLAOverflowFailure0, EmittedDefined,
            WithinSwiftInt, SwiftIntMin, SwiftIntMax

=====================================================================
