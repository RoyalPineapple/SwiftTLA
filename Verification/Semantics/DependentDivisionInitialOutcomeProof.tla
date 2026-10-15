---------------- MODULE DependentDivisionInitialOutcomeProof ----------------
EXTENDS TLAPS, DependentDivisionInitialModel

CONSTANTS failedDivisor, failedOperands

SourceInit == pc = "stay" /\ divisor = 1 /\ quotient = 1
SourceDivisionFailure(failedDivisor) == failedDivisor = 0
SourceOverflowFailure(failedOperands) == FALSE
DroppedDivisionFailure(failedDivisor) == FALSE

THEOREM EmittedInitialStatesMatchSource ==
    ASSUME divisor \in Int, quotient \in Int
    PROVE Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM EmittedDivisionFailureMatchesSource ==
    ASSUME failedDivisor \in Int
    PROVE __SwiftTLAInitialDivisionByZeroFailure2(failedDivisor)
        <=> SourceDivisionFailure(failedDivisor)
    BY SMT DEF __SwiftTLAInitialDivisionByZeroFailure2,
        SourceDivisionFailure

THEOREM EmittedOverflowFailureMatchesSource ==
    ASSUME failedOperands \in Seq(Int)
    PROVE __SwiftTLAInitialOverflowFailure2(failedOperands)
        <=> SourceOverflowFailure(failedOperands)
    BY SMT DEF __SwiftTLAInitialOverflowFailure2,
        SourceOverflowFailure

THEOREM CompleteInitialOutcomeMatchesSource ==
    ASSUME divisor \in Int, quotient \in Int,
        failedDivisor \in Int, failedOperands \in Seq(Int)
    PROVE /\ Init <=> SourceInit
          /\ __SwiftTLAInitialDivisionByZeroFailure2(failedDivisor)
                <=> SourceDivisionFailure(failedDivisor)
          /\ __SwiftTLAInitialOverflowFailure2(failedOperands)
                <=> SourceOverflowFailure(failedOperands)
          /\ __SwiftTLAInitialOverflowOperation2 = "division"
    BY EmittedInitialStatesMatchSource,
        EmittedDivisionFailureMatchesSource,
        EmittedOverflowFailureMatchesSource,
        SMT DEF __SwiftTLAInitialOverflowOperation2

THEOREM DroppingFailureChangesOutcome ==
    __SwiftTLAInitialDivisionByZeroFailure2(0)
        /\ ~DroppedDivisionFailure(0)
    BY SMT DEF __SwiftTLAInitialDivisionByZeroFailure2,
        DroppedDivisionFailure

=============================================================================
