---- MODULE MissingStringSelection ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, selected

vars == <<pc, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __PROOF_MEMBER__ \in {"alpha"} : FALSE) THEN (LET __atomic_0 == (LET __MissingStringSelection_choiceCandidates0 == {__PROOF_MEMBER__ \in {"alpha"} : FALSE} IN (CHOOSE __PROOF_MEMBER__ \in __MissingStringSelection_choiceCandidates0 : (\A __MissingStringSelection_choiceOther1 \in __MissingStringSelection_choiceCandidates0 : (CASE __PROOF_MEMBER__ = "alpha" -> 0) <= (CASE __MissingStringSelection_choiceOther1 = "alpha" -> 0)))) IN ((TRUE /\ selected' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
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
