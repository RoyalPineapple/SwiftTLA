---- MODULE ConditionalStepProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, chooseFirst, value

vars == <<pc, chooseFirst, value>>

choose == (((pc = "choose")) = TRUE /\ (((chooseFirst) = TRUE /\ (LET __atomic_0 == 1 IN ((TRUE /\ value' = __atomic_0) /\ (pc' = "Done" /\ UNCHANGED chooseFirst)))) \/ (((~chooseFirst)) = TRUE /\ (LET __atomic_1 == 2 IN ((TRUE /\ value' = __atomic_1) /\ (pc' = "Done" /\ UNCHANGED chooseFirst))))))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED chooseFirst /\ UNCHANGED value)) /\ UNCHANGED pc)

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
