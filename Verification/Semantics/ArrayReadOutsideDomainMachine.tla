---- MODULE ArrayReadOutsideDomainMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES sequence, result

vars == <<sequence, result>>

read == (IF (IF (1 \in DOMAIN (sequence)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == sequence[1] IN ((TRUE /\ result' = __atomic_0) /\ UNCHANGED sequence)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((1 \in DOMAIN (sequence)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<1, Len(sequence)>>
__SwiftTLAAnyEvaluationFailure0 == ~((IF (1 \in DOMAIN (sequence)) THEN TRUE ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ sequence = <<>>
  /\ result = 0
  /\ (IF (result >= (-2 * 1000000000 - 147483648) /\ result <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE result \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == read

Spec ==
  /\ Init
  /\ [][Next]_<<sequence, result>>

====
