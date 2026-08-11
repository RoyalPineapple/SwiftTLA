---- MODULE BridgeViolation ----
EXTENDS Naturals

VARIABLE x

Init == x = 0
Next == x < 3 /\ x' = x + 1
TypeOK == x \in 0..3
FailsAtThree == x < 3

====
