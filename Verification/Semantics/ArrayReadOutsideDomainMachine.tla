---- MODULE ArrayReadOutsideDomainMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES sequence, result

vars == <<sequence, result>>

read == (IF (IF (1 \in DOMAIN (sequence)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == sequence[1] IN ((TRUE /\ result' = __atomic_0) /\ UNCHANGED sequence)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((1 \in DOMAIN (sequence)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<1, Len(sequence)>>
__SwiftTLAEvaluationOK == ~(__SwiftTLASequenceIndexOutOfBoundsFailure0)

Init ==
  /\ sequence = <<>>
  /\ result = 0

Next == read

Spec ==
  /\ Init
  /\ [][Next]_<<sequence, result>>

====
