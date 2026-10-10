---- MODULE OrderedCopy ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, x, y

vars == <<pc, x, y>>

copy == (((pc = "copy")) = TRUE /\ (LET __atomic_0 == (x + 1) IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\ x' = __atomic_0) /\ (y' = __atomic_1 /\ pc' = "repeatWrites")))))
repeatWrites == (((pc = "repeatWrites")) = TRUE /\ (LET __atomic_2 == (x + 1) IN (LET __atomic_3 == (__atomic_2 + 1) IN ((TRUE /\ x' = __atomic_3) /\ (pc' = "Done" /\ UNCHANGED y)))))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED x /\ UNCHANGED y)) /\ UNCHANGED pc)

Init ==
  /\ pc = "copy"
  /\ x = 1
  /\ y = 0

Next ==
  \/ copy
  \/ repeatWrites
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, x, y>>

====
