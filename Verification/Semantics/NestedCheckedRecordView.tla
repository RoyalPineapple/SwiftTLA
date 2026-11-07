---- MODULE NestedCheckedRecordView ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, record

vars == <<pc, record>>

inspect == (((((pc = "inspect")) = TRUE /\ (IF (IF (DOMAIN record = {"nested"} /\ (FALSE)) THEN TRUE ELSE FALSE) THEN ((Len(((LET _checkedValue == record IN CASE (DOMAIN _checkedValue = {"nested"} /\ (FALSE)) -> _checkedValue)).nested) = 0)) = TRUE ELSE FALSE)) /\ (TRUE /\ pc' = "Done")) /\ UNCHANGED record)
__SwiftTLANoMatchingCaseFailure0 == (((pc = "inspect")) = TRUE /\ ~((DOMAIN record = {"nested"} /\ (FALSE))))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "inspect") THEN ~((IF (DOMAIN record = {"nested"} /\ (FALSE)) THEN TRUE ELSE FALSE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED record /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "inspect"
  /\ record = [nested |-> 1]

Next ==
  \/ inspect
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, record>>

====
