---- MODULE ArrayStepMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES values

append == (((Len(values) < 2)) = TRUE /\ (LET __atomic_0 == Append(values, 1) IN (TRUE /\ values' = __atomic_0)))

bounded == (Len(values) <= 2)

Init == values = <<>>

Next == append

Spec ==
  /\ Init
  /\ [][Next]_values

====
