---------------- MODULE RandomSubsetInitialOutcomeProof ----------------
EXTENDS TLAPS, Integers

SourceInitial(pc, limit, chosen) ==
    pc = "stay" /\ limit \in {-1, 1} /\ limit > 0 /\ chosen \in {7}
RenderedInitial(pc, limit, chosen) ==
    pc = "stay" /\ limit \in {-1, 1} /\ (limit > 0 /\ chosen \in {7})
    /\ (IF (limit >= (-2 * 1000000000 - 147483648) /\ limit <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE limit \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
    /\ (IF (chosen >= (-2 * 1000000000 - 147483648) /\ chosen <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE chosen \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
SourceInvalidCount(failedCount) == failedCount = -1

__SwiftTLAInitialRandomSubsetCountFailure2(__SwiftTLAInitialFailedCount2) == (LET __SwiftTLAInitialValue0 == "stay" IN (\E __SwiftTLAInitialValue1 \in {-1, 1}: (IF (IF (__SwiftTLAInitialValue1 >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue1 <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue1 \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (__SwiftTLAInitialFailedCount2 < 0 /\ __SwiftTLAInitialFailedCount2 = __SwiftTLAInitialValue1) ELSE FALSE)))

THEOREM CompleteInitialOutcomesMatchSource ==
    \A pc : \A limit, chosen, failedCount \in Int :
        /\ (RenderedInitial(pc, limit, chosen) <=> SourceInitial(pc, limit, chosen))
        /\ (__SwiftTLAInitialRandomSubsetCountFailure2(failedCount)
            <=> SourceInvalidCount(failedCount))
    BY SMT DEF RenderedInitial, SourceInitial, SourceInvalidCount,
        __SwiftTLAInitialRandomSubsetCountFailure2

=============================================================================
