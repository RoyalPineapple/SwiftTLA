---- MODULE MissingStringSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, selected

vars == <<pc, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __PROOF_MEMBER__ \in {"alpha"} : FALSE) THEN (LET __atomic_0 == (CHOOSE __PROOF_MEMBER__ \in {"alpha"} : FALSE) IN ((TRUE /\ selected' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __PROOF_MEMBER__ \in {"alpha"} : FALSE)))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "select") THEN ~((\E __PROOF_MEMBER__ \in {"alpha"} : FALSE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED selected /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "select"
  /\ selected = "none"

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, selected>>

====
