---- MODULE BoundBodyChoiceFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES source, result

vars == <<source, result>>

pick == (LET __atomic_0 == source IN (IF (\E __binder_SpecParser_408_0 \in {1} : (__binder_SpecParser_408_0 = __atomic_0)) THEN (LET __atomic_1 == (LET __BoundBodyChoiceFailureModel_choiceCandidates0 == {__binder_SpecParser_408_0 \in {1} : (__binder_SpecParser_408_0 = __atomic_0)} IN (CHOOSE __binder_SpecParser_408_0 \in __BoundBodyChoiceFailureModel_choiceCandidates0 : (\A __BoundBodyChoiceFailureModel_choiceOther1 \in __BoundBodyChoiceFailureModel_choiceCandidates0 : __binder_SpecParser_408_0 <= __BoundBodyChoiceFailureModel_choiceOther1))) IN ((TRUE /\ result' = __atomic_1) /\ UNCHANGED source)) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (LET __atomic_0 == source IN ~((\E __binder_SpecParser_408_0 \in {1} : (__binder_SpecParser_408_0 = __atomic_0))))
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0)

Init ==
  /\ source \in 0..1
  /\ result = 0

Next == pick

Spec ==
  /\ Init
  /\ [][Next]_<<source, result>>

====
