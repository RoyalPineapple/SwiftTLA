---------------- MODULE EitherBranchDivisionFailureProof ----------------
EXTENDS TLAPS, EitherBranchDivisionFailureModel

SourceInit == divisor = 0 /\ result = 0
SourceQuotient == IF divisor < 0 THEN (-1) \div (-divisor) ELSE 1 \div divisor
SourcePick ==
    /\ divisor' = divisor
    /\ \/ result' = 1
       \/ divisor # 0 /\ result' = SourceQuotient
SourceDivisionFailure == divisor = 0
SourceEvaluationOK == ~SourceDivisionFailure
DroppedSuccessfulBranch ==
    /\ divisor # 0
    /\ divisor' = divisor
    /\ result' = SourceQuotient

THEOREM EmittedInitialMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedStepMatchesSource ==
    ASSUME divisor \in Int, result \in Int
    PROVE pick <=> SourcePick
    BY SMT DEF pick, SourcePick, SourceQuotient

THEOREM EmittedDivisionFailureMatchesSource ==
    ASSUME divisor \in Int, result \in Int
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
    BY SMT DEF __SwiftTLADivisionByZeroFailure0,
        __SwiftTLADivisionByZeroDivisor0, SourceDivisionFailure

THEOREM EmittedOverflowIsImpossible ==
    ASSUME divisor \in Int, result \in Int
    PROVE ~__SwiftTLAOverflowFailure0
    BY SMT DEF __SwiftTLAOverflowFailure0

THEOREM EmittedAggregateMatchesDetailedFailures ==
    ASSUME divisor \in Int, result \in Int
    PROVE __SwiftTLAAnyEvaluationFailure0 <=>
        (__SwiftTLADivisionByZeroFailure0 \/ __SwiftTLAOverflowFailure0)
    BY SMT DEF __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLADivisionByZeroFailure0, __SwiftTLAOverflowFailure0

THEOREM CompleteEmittedOutcomeMatchesSource ==
    ASSUME divisor \in Int, result \in Int
    PROVE /\ Init <=> SourceInit
          /\ Next <=> SourcePick
          /\ __SwiftTLADivisionByZeroFailure0 <=> SourceDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedInitialMatchesSource, EmittedStepMatchesSource,
        EmittedDivisionFailureMatchesSource, EmittedOverflowIsImpossible,
        EmittedAggregateMatchesDetailedFailures,
        SMT DEF Next,
            __SwiftTLAEvaluationOK, SourceEvaluationOK

THEOREM DroppingSuccessfulBranchChangesOutcome ==
    ASSUME divisor = 0, divisor' = 0, result' = 1
    PROVE SourcePick /\ ~DroppedSuccessfulBranch
    BY SMT DEF SourcePick, DroppedSuccessfulBranch

=============================================================================
