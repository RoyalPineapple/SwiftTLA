---- MODULE FallibleSequenceHeadMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES values, length, result

vars == <<values, length, result>>

readHead == (IF (IF (length <= Len(values)) THEN (IF Len(SubSeq(values, 1, length)) > 0 THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_0 == Head(SubSeq(values, 1, length)) IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED values /\ UNCHANGED length))) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((length <= Len(values)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<length, Len(values)>>
__SwiftTLAEmptySequenceFailure0 == (IF (length <= Len(values)) THEN ~(Len(SubSeq(values, 1, length)) > 0) ELSE FALSE)
__SwiftTLAAnyEvaluationFailure0 == ~((IF (length <= Len(values)) THEN (IF Len(SubSeq(values, 1, length)) > 0 THEN TRUE ELSE FALSE) ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ values = <<1>>
  /\ length \in 0..2
  /\ result = 0
  /\ (IF (length >= (-2 * 1000000000 - 147483648) /\ length <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE length \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (result >= (-2 * 1000000000 - 147483648) /\ result <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE result \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == readHead

Spec ==
  /\ Init
  /\ [][Next]_<<values, length, result>>

====
