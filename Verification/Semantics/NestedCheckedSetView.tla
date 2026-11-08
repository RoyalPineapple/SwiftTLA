---- MODULE NestedCheckedSetView ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, members

vars == <<pc, members>>

inspect == (((((pc = "inspect")) = TRUE /\ (IF (IF (\A _shapeMember0 \in members : FALSE) THEN TRUE ELSE FALSE) THEN ((Cardinality((LET _checkedValue == members IN CASE (\A _shapeMember0 \in _checkedValue : FALSE) -> _checkedValue)) = 0)) = TRUE ELSE FALSE)) /\ (TRUE /\ pc' = "Done")) /\ UNCHANGED members)
__SwiftTLANoMatchingCaseFailure0 == (((pc = "inspect")) = TRUE /\ ~((\A _shapeMember0 \in members : FALSE)))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "inspect") THEN ~((IF (\A _shapeMember0 \in members : FALSE) THEN TRUE ELSE FALSE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED members /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "inspect"
  /\ members = {1}

Next ==
  \/ inspect
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, members>>

====
