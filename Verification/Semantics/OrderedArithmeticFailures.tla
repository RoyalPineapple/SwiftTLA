-------------------- MODULE OrderedArithmeticFailures --------------------
EXTENDS Integers, TLAPS

SourceFirstDivisionOutcome(divisor) ==
    IF divisor = 0 THEN "divisionByZero" ELSE "continue"
EmittedDivisionByZeroFailure(divisor) == ~(divisor # 0)
EmittedLaterFailure(divisor, candidate) ==
    IF divisor # 0 THEN candidate ELSE FALSE
EmittedFirstDivisionOutcome(divisor) ==
    IF EmittedDivisionByZeroFailure(divisor)
    THEN "divisionByZero"
    ELSE "continue"

THEOREM FirstDivisionFailurePrecedesEveryLaterFailure ==
    ASSUME NEW divisor \in Int, NEW candidate \in BOOLEAN,
           divisor = 0
    PROVE /\ EmittedFirstDivisionOutcome(divisor)
                = SourceFirstDivisionOutcome(divisor)
          /\ ~EmittedLaterFailure(divisor, candidate)
    BY SMT DEF SourceFirstDivisionOutcome,
        EmittedDivisionByZeroFailure, EmittedLaterFailure,
        EmittedFirstDivisionOutcome

ReversedFirstOutcome(divisor, candidate) ==
    IF candidate THEN "overflow"
    ELSE EmittedFirstDivisionOutcome(divisor)

THEOREM ReversingFailureOrderChangesTheObservedOutcome ==
    ReversedFirstOutcome(0, TRUE) # SourceFirstDivisionOutcome(0)
    BY SMT DEF ReversedFirstOutcome, EmittedFirstDivisionOutcome,
        EmittedDivisionByZeroFailure, SourceFirstDivisionOutcome

SourceRightFirstMembershipOutcome(divisor, memberOverflows) ==
    IF divisor = 0 THEN "divisionByZero"
    ELSE IF memberOverflows THEN "overflow" ELSE "value"
EmittedRightFirstMembershipOutcome(divisor, memberOverflows) ==
    IF EmittedDivisionByZeroFailure(divisor) THEN "divisionByZero"
    ELSE IF EmittedLaterFailure(divisor, memberOverflows)
         THEN "overflow" ELSE "value"

THEOREM MembershipFailureOrderMatchesForEveryDivisor ==
    ASSUME NEW divisor \in Int, NEW memberOverflows \in BOOLEAN
    PROVE SourceRightFirstMembershipOutcome(divisor, memberOverflows)
        = EmittedRightFirstMembershipOutcome(divisor, memberOverflows)
    BY SMT DEF SourceRightFirstMembershipOutcome,
        EmittedRightFirstMembershipOutcome,
        EmittedDivisionByZeroFailure, EmittedLaterFailure

SourceModuloOutcome(divisor) ==
    IF divisor = 0 THEN "divisionByZero"
    ELSE IF divisor < 0 THEN "negativeModuloDivisor"
    ELSE "value"
EmittedNegativeModuloDivisorFailure(divisor) ==
    IF divisor # 0 THEN ~(divisor > 0) ELSE FALSE
EmittedModuloOutcome(divisor) ==
    IF EmittedDivisionByZeroFailure(divisor) THEN "divisionByZero"
    ELSE IF EmittedNegativeModuloDivisorFailure(divisor)
         THEN "negativeModuloDivisor"
         ELSE "value"

THEOREM ModuloFailureOrderMatchesSource ==
    ASSUME NEW divisor \in Int
    PROVE EmittedModuloOutcome(divisor) = SourceModuloOutcome(divisor)
    BY SMT DEF SourceModuloOutcome, EmittedModuloOutcome,
        EmittedDivisionByZeroFailure,
        EmittedNegativeModuloDivisorFailure

=============================================================================
