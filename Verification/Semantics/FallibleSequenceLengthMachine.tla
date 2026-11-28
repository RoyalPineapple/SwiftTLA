---- MODULE FallibleSequenceLengthMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES values, length, result

vars == <<values, length, result>>

measure == (IF (IF (length <= Len(values)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == Len(SubSeq(values, 1, length)) IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED values /\ UNCHANGED length))) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((length <= Len(values)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<length, Len(values)>>
__SwiftTLAAnyEvaluationFailure0 == ~((IF (length <= Len(values)) THEN TRUE ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ values = <<1>>
  /\ length \in 1..2
  /\ result = 0
  /\ (IF (length >= (-2 * 1000000000 - 147483648) /\ length <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE length \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (result >= (-2 * 1000000000 - 147483648) /\ result <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE result \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == measure

Spec ==
  /\ Init
  /\ [][Next]_<<values, length, result>>

====
