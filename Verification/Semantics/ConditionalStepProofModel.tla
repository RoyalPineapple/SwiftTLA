---- MODULE ConditionalStepProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, chooseFirst, value

vars == <<pc, chooseFirst, value>>

choose == (((pc = "choose")) = TRUE /\ ((LET __atomic_0 == (~chooseFirst) IN ((__atomic_0) = TRUE /\ (LET __atomic_1 == 1 IN ((TRUE /\ chooseFirst' = __atomic_0) /\ (value' = __atomic_1 /\ pc' = "Done"))))) \/ (LET __atomic_0 == (~chooseFirst) IN (((~__atomic_0)) = TRUE /\ (LET __atomic_2 == 2 IN ((TRUE /\ chooseFirst' = __atomic_0) /\ (value' = __atomic_2 /\ pc' = "Done")))))))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED chooseFirst /\ UNCHANGED value)) /\ UNCHANGED pc)

Init ==
  /\ pc = "choose"
  /\ chooseFirst \in {FALSE, TRUE}
  /\ value = 0
  /\ (IF (value >= (-2 * 1000000000 - 147483648) /\ value <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE value \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next ==
  \/ choose
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, chooseFirst, value>>
  /\ WF_<<pc, chooseFirst, value>>(Next)

====
