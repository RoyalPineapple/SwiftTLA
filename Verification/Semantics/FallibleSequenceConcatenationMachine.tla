---- MODULE FallibleSequenceConcatenationMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES front, back, frontLength, backLength

vars == <<front, back, frontLength, backLength>>

combine == (IF (IF (frontLength <= Len(front)) THEN (IF (backLength <= Len(back)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_0 == (SubSeq(front, 1, frontLength) \o SubSeq(back, 1, backLength)) IN (((TRUE /\ front' = __atomic_0) /\ (UNCHANGED back /\ UNCHANGED frontLength)) /\ UNCHANGED backLength)) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsFailure0 == ~((frontLength <= Len(front)))
__SwiftTLASequenceIndexOutOfBoundsOperands0 == <<frontLength, Len(front)>>
__SwiftTLASequenceIndexOutOfBoundsFailure0_1 == (IF (frontLength <= Len(front)) THEN ~((backLength <= Len(back))) ELSE FALSE)
__SwiftTLASequenceIndexOutOfBoundsOperands0_1 == <<backLength, Len(back)>>
__SwiftTLAAnyEvaluationFailure0 == ~((IF (frontLength <= Len(front)) THEN (IF (backLength <= Len(back)) THEN TRUE ELSE FALSE) ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ front = <<1>>
  /\ back = <<2, 2>>
  /\ frontLength \in 1..2
  /\ backLength \in 2..3

Next == combine

Spec ==
  /\ Init
  /\ [][Next]_<<front, back, frontLength, backLength>>

====
