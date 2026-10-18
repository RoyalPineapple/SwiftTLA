---- MODULE EmptySequenceReadMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES sequence, head, tail

vars == <<sequence, head, tail>>

readHead == (IF (IF Len(sequence) > 0 THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == Head(sequence) IN ((TRUE /\ head' = __atomic_0) /\ (UNCHANGED sequence /\ UNCHANGED tail))) ELSE FALSE)
__SwiftTLAEmptySequenceFailure0 == ~(Len(sequence) > 0)
__SwiftTLAAnyEvaluationFailure0 == ~((IF Len(sequence) > 0 THEN TRUE ELSE FALSE))
readTail == (IF (IF Len(sequence) > 0 THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == Tail(sequence) IN ((TRUE /\ tail' = __atomic_0) /\ (UNCHANGED sequence /\ UNCHANGED head))) ELSE FALSE)
__SwiftTLAEmptySequenceFailure1 == ~(Len(sequence) > 0)
__SwiftTLAAnyEvaluationFailure1 == ~((IF Len(sequence) > 0 THEN TRUE ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0) /\ ~(__SwiftTLAAnyEvaluationFailure1)

Init ==
  /\ sequence = <<>>
  /\ head = 0
  /\ tail = <<>>

Next ==
  \/ readHead
  \/ readTail

Spec ==
  /\ Init
  /\ [][Next]_<<sequence, head, tail>>

====
