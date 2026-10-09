---- MODULE GeneratedAtomicCopyProofModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES first, second

vars == <<first, second>>

copy == (LET __atomic_0 == second IN (LET __atomic_1 == __atomic_0 IN (IF (IF TRUE THEN first' = __atomic_0 ELSE FALSE) THEN second' = __atomic_1 ELSE FALSE)))

Init ==
  /\ first = 0
  /\ second = 1

Next == copy

Spec ==
  /\ Init
  /\ [][Next]_<<first, second>>

====
