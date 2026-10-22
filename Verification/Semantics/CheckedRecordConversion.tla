---- MODULE CheckedRecordConversion ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, record

vars == <<pc, record>>

valid == (((((pc = "valid")) = TRUE /\ (IF (IF (DOMAIN record = {"count"} /\ (record["count"] \in {0})) THEN TRUE ELSE FALSE) THEN ((((LET _checkedValue == record IN CASE (DOMAIN _checkedValue = {"count"} /\ (_checkedValue["count"] \in {0})) -> _checkedValue)).count = 0)) = TRUE ELSE FALSE)) /\ (TRUE /\ pc' = "change")) /\ UNCHANGED record)
__SwiftTLANoMatchingCaseFailure0 == (((pc = "valid")) = TRUE /\ ~((DOMAIN record = {"count"} /\ (record["count"] \in {0}))))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "valid") THEN ~((IF (DOMAIN record = {"count"} /\ (record["count"] \in {0})) THEN TRUE ELSE FALSE)) ELSE FALSE)
change == (((pc = "change")) = TRUE /\ (LET __atomic_0 == [record EXCEPT !["count"] = 1] IN ((TRUE /\ record' = __atomic_0) /\ pc' = "invalid")))
invalid == (((((pc = "invalid")) = TRUE /\ (IF (IF (DOMAIN record = {"count"} /\ (record["count"] \in {0})) THEN TRUE ELSE FALSE) THEN ((((LET _checkedValue == record IN CASE (DOMAIN _checkedValue = {"count"} /\ (_checkedValue["count"] \in {0})) -> _checkedValue)).count = 0)) = TRUE ELSE FALSE)) /\ (TRUE /\ pc' = "Done")) /\ UNCHANGED record)
__SwiftTLANoMatchingCaseFailure2 == (((pc = "invalid")) = TRUE /\ ~((DOMAIN record = {"count"} /\ (record["count"] \in {0}))))
__SwiftTLAAnyEvaluationFailure2 == (IF (pc = "invalid") THEN ~((IF (DOMAIN record = {"count"} /\ (record["count"] \in {0})) THEN TRUE ELSE FALSE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED record /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0) /\ ~(__SwiftTLAAnyEvaluationFailure2)

Init ==
  /\ pc = "valid"
  /\ record = [count |-> 0]

Next ==
  \/ valid
  \/ change
  \/ invalid
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, record>>

====
