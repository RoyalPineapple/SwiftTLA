---- MODULE TemporalSymmetry ----
EXTENDS FiniteSets

CONSTANT Members
VARIABLE chosen

Init == chosen = {}
Choose(m) == /\ m \in Members
             /\ chosen' = chosen \cup {m}
Next == \E m \in Members : Choose(m)
Symmetry == Permutations(Members)
EventuallyChosen == <>(chosen # {})
Spec == Init /\ [][Next]_chosen
====
