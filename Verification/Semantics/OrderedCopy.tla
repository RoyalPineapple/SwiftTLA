---- MODULE OrderedCopy ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, x, y

vars == <<pc, x, y>>

copy == (IF ((pc = "copy")) = TRUE THEN (LET __atomic_0 == (x + 1) IN (LET __atomic_1 == __atomic_0 IN (IF (IF TRUE THEN x' = __atomic_0 ELSE FALSE) THEN (IF y' = __atomic_1 THEN pc' = "repeatWrites" ELSE FALSE) ELSE FALSE))) ELSE FALSE)
repeatWrites == (IF ((pc = "repeatWrites")) = TRUE THEN (LET __atomic_2 == (x + 1) IN (LET __atomic_3 == (__atomic_2 + 1) IN (IF (IF TRUE THEN x' = __atomic_3 ELSE FALSE) THEN (IF pc' = "Done" THEN UNCHANGED y ELSE FALSE) ELSE FALSE))) ELSE FALSE)
Terminating == (IF (IF (IF ((pc = "Done")) = TRUE THEN UNCHANGED pc ELSE FALSE) THEN (IF UNCHANGED x THEN UNCHANGED y ELSE FALSE) ELSE FALSE) THEN UNCHANGED pc ELSE FALSE)

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
