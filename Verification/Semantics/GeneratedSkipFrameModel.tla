---- MODULE GeneratedSkipFrameModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES value

stay == (TRUE /\ UNCHANGED value)

Preserved == (value = 0)

Init ==
  /\ value = 0
  /\ (IF (value >= (-2 * 1000000000 - 147483648) /\ value <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE value \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == stay

Spec ==
  /\ Init
  /\ [][Next]_value

====
