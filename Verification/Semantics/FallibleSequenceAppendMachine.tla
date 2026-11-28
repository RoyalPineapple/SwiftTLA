---- MODULE FallibleSequenceAppendMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES values, length

vars == <<values, length>>

append == (IF (IF (length <= Len(values)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == Append(SubSeq(values, 1, length), 3) IN ((TRUE /\ values' = __atomic_0) /\ UNCHANGED length)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((length <= Len(values)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<length, Len(values)>>
__SwiftTLAAnyEvaluationFailure0 == ~((IF (length <= Len(values)) THEN TRUE ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ values = <<1>>
  /\ length \in 1..2
  /\ (IF (length >= (-2 * 1000000000 - 147483648) /\ length <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE length \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == append

Spec ==
  /\ Init
  /\ [][Next]_<<values, length>>

====
