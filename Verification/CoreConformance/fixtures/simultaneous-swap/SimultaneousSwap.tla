---------------------- MODULE SimultaneousSwap ----------------------
VARIABLES left, right

Init == left = 1 /\ right = 2

Swap == left' = right /\ right' = left

Next == Swap

Spec == Init /\ [][Next]_<<left, right>>

TypeOK == left \in {1, 2} /\ right \in {1, 2}
=====================================================================
