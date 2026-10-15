---- MODULE ConditionalSelectionFailure ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, attempt, selected

vars == <<pc, attempt, selected>>

select == (((pc = "select")) = TRUE /\ (((attempt) = TRUE /\ (IF (\E __SELECT_MEMBER__ \in {1} : FALSE) THEN (LET __atomic_0 == (LET __ConditionalSelectionFailure_choiceCandidates0 == {__SELECT_MEMBER__ \in {1} : FALSE} IN (CHOOSE __SELECT_MEMBER__ \in __ConditionalSelectionFailure_choiceCandidates0 : (\A __ConditionalSelectionFailure_choiceOther1 \in __ConditionalSelectionFailure_choiceCandidates0 : __SELECT_MEMBER__ <= __ConditionalSelectionFailure_choiceOther1))) IN ((TRUE /\ selected' = __atomic_0) /\ (pc' = "Done" /\ UNCHANGED attempt))) ELSE FALSE)) \/ (((~attempt)) = TRUE /\ (LET __atomic_1 == 2 IN ((TRUE /\ selected' = __atomic_1) /\ (pc' = "Done" /\ UNCHANGED attempt))))))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ((attempt) = TRUE /\ ~((\E __SELECT_MEMBER__ \in {1} : FALSE))))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED attempt /\ UNCHANGED selected)) /\ UNCHANGED pc)
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0)

Init ==
  /\ pc = "select"
  /\ attempt \in {FALSE, TRUE}
  /\ selected = 0

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, attempt, selected>>

====
