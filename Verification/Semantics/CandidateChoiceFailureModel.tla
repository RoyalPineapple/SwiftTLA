---- MODULE CandidateChoiceFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES result

pick == (\E __atomic_0 \in 0..1: (IF (\E __binder_SpecParser_362_0 \in {1} : (__binder_SpecParser_362_0 = __atomic_0)) THEN (LET __atomic_1 == (LET __CandidateChoiceFailureModel_choiceCandidates0 == {__binder_SpecParser_362_0 \in {1} : (__binder_SpecParser_362_0 = __atomic_0)} IN (CHOOSE __binder_SpecParser_362_0 \in __CandidateChoiceFailureModel_choiceCandidates0 : (\A __CandidateChoiceFailureModel_choiceOther1 \in __CandidateChoiceFailureModel_choiceCandidates0 : __binder_SpecParser_362_0 <= __CandidateChoiceFailureModel_choiceOther1))) IN (TRUE /\ result' = __atomic_1)) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (LET __SwiftTLAFailedCandidates0 == {__atomic_0 \in 0..1: ~((\E __binder_SpecParser_362_0 \in {1} : (__binder_SpecParser_362_0 = __atomic_0)))} IN (IF __SwiftTLAFailedCandidates0 = {} THEN FALSE ELSE (LET __atomic_0 == (CHOOSE __SwiftTLAFirstFailingCandidate0 \in __SwiftTLAFailedCandidates0: \A __SwiftTLAEarlierCandidate0 \in __SwiftTLAFailedCandidates0: __SwiftTLAFirstFailingCandidate0 <= __SwiftTLAEarlierCandidate0) IN ~((\E __binder_SpecParser_362_0 \in {1} : (__binder_SpecParser_362_0 = __atomic_0))))))
__SwiftTLAAnyEvaluationFailure0 == (\E __atomic_0 \in 0..1: ~((\E __binder_SpecParser_362_0 \in {1} : (__binder_SpecParser_362_0 = __atomic_0))))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init == result = 0

Next == pick

Spec ==
  /\ Init
  /\ [][Next]_result

====
