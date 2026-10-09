---- MODULE ConditionalStepProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, chooseFirst, value

vars == <<pc, chooseFirst, value>>

choose == (IF ((pc = "choose")) = TRUE THEN ((LET __atomic_0 == (~chooseFirst) IN (IF (__atomic_0) = TRUE THEN (LET __atomic_1 == 1 IN (IF (IF TRUE THEN chooseFirst' = __atomic_0 ELSE FALSE) THEN (IF value' = __atomic_1 THEN pc' = "Done" ELSE FALSE) ELSE FALSE)) ELSE FALSE)) \/ (LET __atomic_0 == (~chooseFirst) IN (IF ((~__atomic_0)) = TRUE THEN (LET __atomic_2 == 2 IN (IF (IF TRUE THEN chooseFirst' = __atomic_0 ELSE FALSE) THEN (IF value' = __atomic_2 THEN pc' = "Done" ELSE FALSE) ELSE FALSE)) ELSE FALSE))) ELSE FALSE)
Terminating == (IF (IF (IF ((pc = "Done")) = TRUE THEN UNCHANGED pc ELSE FALSE) THEN (IF UNCHANGED chooseFirst THEN UNCHANGED value ELSE FALSE) ELSE FALSE) THEN UNCHANGED pc ELSE FALSE)

Init ==
  /\ pc = "choose"
  /\ chooseFirst \in {FALSE, TRUE}
  /\ value = 0

Next ==
  \/ choose
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, chooseFirst, value>>

====
