---- MODULE FiniteCheckedRecordView ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, level

vars == <<pc, level>>

inspect == (((((pc = "inspect")) = TRUE /\ (IF (IF FALSE THEN TRUE ELSE FALSE) THEN ((((LET _checkedValue == level IN CASE FALSE -> _checkedValue)).count = 0)) = TRUE ELSE FALSE)) /\ (TRUE /\ pc' = "Done")) /\ UNCHANGED level)
__SwiftTLANoMatchingCaseFailure0 == (((pc = "inspect")) = TRUE /\ ~(FALSE))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "inspect") THEN ~((IF FALSE THEN TRUE ELSE FALSE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED level /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "inspect"
  /\ level = 1

Next ==
  \/ inspect
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, level>>

====
