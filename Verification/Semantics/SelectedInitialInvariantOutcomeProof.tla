---------------- MODULE SelectedInitialInvariantOutcomeProof ----------------
EXTENDS TLAPS, SelectedInitialInvariantFailureModel

CONSTANTS failedDivisor, failedOperands

SourceInit == pc = "stay" /\ divisor = 1 /\ quotient = 1
SourceSelectionFailure(value) == value = 0
SourceOverflowFailure(value) == FALSE
DroppedSelectionFilter == pc = "stay" /\ divisor \in {0, 1} /\ quotient = 1
DroppedFailure(value) == FALSE

THEOREM EmittedInitialStatesMatchSource ==
    ASSUME divisor \in Int, quotient \in Int
    PROVE Init <=> SourceInit
    BY SMT DEF Init, Allowed, SourceInit

THEOREM EmittedSelectionFailureMatchesSource ==
    ASSUME failedDivisor \in Int
    PROVE __SwiftTLASelectedInitialDivisionByZeroFailure(failedDivisor)
        <=> SourceSelectionFailure(failedDivisor)
    BY SMT DEF __SwiftTLASelectedInitialDivisionByZeroFailure,
        SourceSelectionFailure

THEOREM EmittedOverflowFailureMatchesSource ==
    ASSUME failedOperands \in Seq(Int)
    PROVE __SwiftTLASelectedInitialOverflowFailure(failedOperands)
        <=> SourceOverflowFailure(failedOperands)
    BY SMT DEF __SwiftTLASelectedInitialOverflowFailure,
        SourceOverflowFailure

THEOREM CompleteInitialOutcomeMatchesSource ==
    ASSUME divisor \in Int, quotient \in Int,
        failedDivisor \in Int, failedOperands \in Seq(Int)
    PROVE /\ Init <=> SourceInit
          /\ __SwiftTLASelectedInitialDivisionByZeroFailure(failedDivisor)
                <=> SourceSelectionFailure(failedDivisor)
          /\ __SwiftTLASelectedInitialOverflowFailure(failedOperands)
                <=> SourceOverflowFailure(failedOperands)
          /\ __SwiftTLASelectedInitialOverflowOperation = "division"
    BY EmittedInitialStatesMatchSource,
        EmittedSelectionFailureMatchesSource,
        EmittedOverflowFailureMatchesSource,
        SMT DEF __SwiftTLASelectedInitialOverflowOperation

THEOREM DroppingFilterAdmitsFailedCandidate ==
    ASSUME pc = "stay", divisor = 0, quotient = 1
    PROVE DroppedSelectionFilter /\ ~Init
        /\ __SwiftTLASelectedInitialDivisionByZeroFailure(0)
    BY SMT DEF DroppedSelectionFilter, Init,
        __SwiftTLASelectedInitialDivisionByZeroFailure

THEOREM DroppingFailureLosesAnOutcome ==
    __SwiftTLASelectedInitialDivisionByZeroFailure(0) /\ ~DroppedFailure(0)
    BY SMT DEF __SwiftTLASelectedInitialDivisionByZeroFailure,
        DroppedFailure

=============================================================================
