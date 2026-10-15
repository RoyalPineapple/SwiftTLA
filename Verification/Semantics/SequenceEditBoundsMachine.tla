---- MODULE SequenceEditBoundsMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES row, position

vars == <<row, position>>

remove == (IF (IF (position \in DOMAIN (row)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == (SubSeq(row, 1, (position - 1)) \o SubSeq(row, (position + 1), Len(row))) IN ((TRUE /\ row' = __atomic_0) /\ UNCHANGED position)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((position \in DOMAIN (row)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<position, Len(row)>>
prefix == (IF (IF (position <= Len(row)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == SubSeq(row, 1, position) IN ((TRUE /\ row' = __atomic_0) /\ UNCHANGED position)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure1 == ~((position <= Len(row)))
__SwiftTLASequenceIndexOutOfBoundsOperands1 == <<position, Len(row)>>
__SwiftTLAEvaluationOK == ~(__SwiftTLASequenceIndexOutOfBoundsFailure0) /\ ~(__SwiftTLASequenceIndexOutOfBoundsFailure1)

Init ==
  /\ row = <<4, 5>>
  /\ position \in 2..3

Next ==
  \/ remove
  \/ prefix

Spec ==
  /\ Init
  /\ [][Next]_<<row, position>>

====
