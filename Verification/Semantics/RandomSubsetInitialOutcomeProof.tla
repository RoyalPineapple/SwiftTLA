---------------- MODULE RandomSubsetInitialOutcomeProof ----------------
EXTENDS TLAPS, Integers

SourceInitial(pc, limit, chosen) ==
    pc = "stay" /\ limit \in {-1, 1} /\ limit > 0 /\ chosen \in {7}
RenderedInitial(pc, limit, chosen) ==
    pc = "stay" /\ limit \in {-1, 1} /\ (limit > 0 /\ chosen \in {7})
SourceInvalidCount(failedCount) == failedCount = -1

__SwiftTLAInitialRandomSubsetCountFailure2(__SwiftTLAInitialFailedCount2) == (LET __SwiftTLAInitialValue0 == "stay" IN (\E __SwiftTLAInitialValue1 \in {-1, 1}: (__SwiftTLAInitialFailedCount2 < 0 /\ __SwiftTLAInitialFailedCount2 = __SwiftTLAInitialValue1)))

THEOREM CompleteInitialOutcomesMatchSource ==
    \A pc : \A limit, chosen, failedCount \in Int :
        /\ (RenderedInitial(pc, limit, chosen) <=> SourceInitial(pc, limit, chosen))
        /\ (__SwiftTLAInitialRandomSubsetCountFailure2(failedCount)
            <=> SourceInvalidCount(failedCount))
    BY SMT DEF RenderedInitial, SourceInitial, SourceInvalidCount,
        __SwiftTLAInitialRandomSubsetCountFailure2

=============================================================================
