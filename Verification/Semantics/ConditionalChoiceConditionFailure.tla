---- MODULE ConditionalChoiceConditionFailure ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, selected

vars == <<pc, selected>>

select == (((pc = "select")) = TRUE /\ (((IF (\E __CONDITION_MEMBER__ \in {TRUE} : FALSE) THEN ((LET __ConditionalChoiceConditionFailure_choiceCandidates0 == {__CONDITION_MEMBER__ \in {TRUE} : FALSE} IN (CHOOSE __CONDITION_MEMBER__ \in __ConditionalChoiceConditionFailure_choiceCandidates0 : (\A __ConditionalChoiceConditionFailure_choiceOther1 \in __ConditionalChoiceConditionFailure_choiceCandidates0 : (__CONDITION_MEMBER__ = FALSE \/ __ConditionalChoiceConditionFailure_choiceOther1 = TRUE))))) = TRUE ELSE FALSE) /\ (LET __atomic_0 == 1 IN ((TRUE /\ selected' = __atomic_0) /\ pc' = "Done"))) \/ ((IF (\E __CONDITION_MEMBER__ \in {TRUE} : FALSE) THEN ((~(LET __ConditionalChoiceConditionFailure_choiceCandidates0 == {__CONDITION_MEMBER__ \in {TRUE} : FALSE} IN (CHOOSE __CONDITION_MEMBER__ \in __ConditionalChoiceConditionFailure_choiceCandidates0 : (\A __ConditionalChoiceConditionFailure_choiceOther1 \in __ConditionalChoiceConditionFailure_choiceCandidates0 : (__CONDITION_MEMBER__ = FALSE \/ __ConditionalChoiceConditionFailure_choiceOther1 = TRUE)))))) = TRUE ELSE FALSE) /\ (LET __atomic_1 == 2 IN ((TRUE /\ selected' = __atomic_1) /\ pc' = "Done")))))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ (~((\E __CONDITION_MEMBER__ \in {TRUE} : FALSE)) \/ ~((\E __CONDITION_MEMBER__ \in {TRUE} : FALSE))))
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED selected /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0)

Init ==
  /\ pc = "select"
  /\ selected = 0

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, selected>>

====
