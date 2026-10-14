---- MODULE GeneratedSkipFrameModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES value

stay == (TRUE /\ UNCHANGED value)

Preserved == (value = 0)

Init == value = 0

Next == stay

Spec ==
  /\ Init
  /\ [][Next]_value

====
