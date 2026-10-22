---- MODULE SequenceEditBoundsMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES row, position

vars == <<row, position>>

remove == (IF (IF (position \in DOMAIN (row)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == (SubSeq(row, 1, (position - 1)) \o SubSeq(row, (position + 1), Len(row))) IN ((TRUE /\ row' = __atomic_0) /\ UNCHANGED position)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((position \in DOMAIN (row)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<position, Len(row)>>
__SwiftTLAAnyEvaluationFailure0 == ~((IF (position \in DOMAIN (row)) THEN TRUE ELSE FALSE))
prefix == (IF (IF (position <= Len(row)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == SubSeq(row, 1, position) IN ((TRUE /\ row' = __atomic_0) /\ UNCHANGED position)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure1 == ~((position <= Len(row)))
__SwiftTLASequenceIndexOutOfBoundsOperands1 == <<position, Len(row)>>
__SwiftTLAAnyEvaluationFailure1 == ~((IF (position <= Len(row)) THEN TRUE ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0) /\ ~(__SwiftTLAAnyEvaluationFailure1)

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
