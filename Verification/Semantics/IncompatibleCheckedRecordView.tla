---- MODULE IncompatibleCheckedRecordView ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, count

vars == <<pc, count>>

inspect == (((((pc = "inspect")) = TRUE /\ (IF (IF FALSE THEN TRUE ELSE FALSE) THEN ((((LET _checkedValue == count IN CASE FALSE -> _checkedValue)).count = 0)) = TRUE ELSE FALSE)) /\ (TRUE /\ pc' = "Done")) /\ UNCHANGED count)
__SwiftTLANoMatchingCaseFailure0 == (((pc = "inspect")) = TRUE /\ ~(FALSE))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "inspect") THEN ~((IF FALSE THEN TRUE ELSE FALSE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED count /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "inspect"
  /\ count = 1
  /\ (IF (count >= (-2 * 1000000000 - 147483648) /\ count <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE count \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next ==
  \/ inspect
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, count>>

====
