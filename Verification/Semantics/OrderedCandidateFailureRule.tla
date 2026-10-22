---------------- MODULE OrderedCandidateFailureRule ----------------
EXTENDS Integers, FiniteSets, TLAPS

Candidates == 0..1
DivisionFailure(candidate) == candidate = 0
ModuloFailure(candidate) == candidate = 1
AnyFailure(candidate) == DivisionFailure(candidate) \/ ModuloFailure(candidate)

THEOREM CanonicalIntegerFailureCandidate ==
    ASSUME NEW failed \in SUBSET Int,
           NEW minimum \in failed,
           \A earlier \in failed : minimum <= earlier
    PROVE (CHOOSE first \in failed :
              \A earlier \in failed : first <= earlier) = minimum
    BY SMT

FirstFailingCandidate ==
    LET failed == {candidate \in Candidates : AnyFailure(candidate)}
    IN IF failed = {} THEN -1
       ELSE CHOOSE first \in failed :
           \A earlier \in failed : first <= earlier

ReversedCandidateOrder ==
    LET failed == {candidate \in Candidates : AnyFailure(candidate)}
    IN CHOOSE first \in failed :
        \A earlier \in failed : first >= earlier

EmittedDivisionFailure ==
    LET failed == {candidate \in Candidates : AnyFailure(candidate)}
    IN IF failed = {} THEN FALSE
       ELSE LET candidate ==
           (CHOOSE first \in failed :
               \A earlier \in failed : first <= earlier)
           IN DivisionFailure(candidate)

EmittedModuloFailure ==
    LET failed == {candidate \in Candidates : AnyFailure(candidate)}
    IN IF failed = {} THEN FALSE
       ELSE LET candidate ==
           (CHOOSE first \in failed :
               \A earlier \in failed : first <= earlier)
           IN ModuloFailure(candidate)

THEOREM FirstFailureIsLeast == FirstFailingCandidate = 0
    BY CanonicalIntegerFailureCandidate, SMT DEF FirstFailingCandidate, Candidates, AnyFailure,
        DivisionFailure, ModuloFailure

THEOREM DivisionWins == EmittedDivisionFailure /\ ~EmittedModuloFailure
    BY FirstFailureIsLeast, SMT DEF EmittedDivisionFailure,
        EmittedModuloFailure, Candidates, AnyFailure,
        DivisionFailure, ModuloFailure, FirstFailingCandidate

THEOREM ReversedOrderChangesTheVerdict ==
    ReversedCandidateOrder = 1 /\ ModuloFailure(ReversedCandidateOrder)
    BY SMT DEF ReversedCandidateOrder, Candidates, AnyFailure,
        DivisionFailure, ModuloFailure

=============================================================================
