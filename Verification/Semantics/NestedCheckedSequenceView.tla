---- MODULE NestedCheckedSequenceView ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, numbers

vars == <<pc, numbers>>

inspect == (((((pc = "inspect")) = TRUE /\ (IF (IF (DOMAIN numbers = 1..Len(numbers) /\ (\A _shapeMember0 \in DOMAIN numbers : FALSE)) THEN TRUE ELSE FALSE) THEN (((LET _checkedValue == numbers IN CASE (DOMAIN _checkedValue = 1..Len(_checkedValue) /\ (\A _shapeMember0 \in DOMAIN _checkedValue : FALSE)) -> _checkedValue) = <<<<1>>>>)) = TRUE ELSE FALSE)) /\ (TRUE /\ pc' = "Done")) /\ UNCHANGED numbers)
__SwiftTLANoMatchingCaseFailure0 == (((pc = "inspect")) = TRUE /\ ~((DOMAIN numbers = 1..Len(numbers) /\ (\A _shapeMember0 \in DOMAIN numbers : FALSE))))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "inspect") THEN ~((IF (DOMAIN numbers = 1..Len(numbers) /\ (\A _shapeMember0 \in DOMAIN numbers : FALSE)) THEN TRUE ELSE FALSE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED numbers /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "inspect"
  /\ numbers = <<1>>

Next ==
  \/ inspect
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, numbers>>

====
