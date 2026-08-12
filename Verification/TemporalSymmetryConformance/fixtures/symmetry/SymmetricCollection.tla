---- MODULE SymmetricCollection ----
EXTENDS FiniteSets, TLC

CONSTANT Members
VARIABLE chosen

Init == chosen = {}
Choose(m) == /\ m \in Members
             /\ chosen' = chosen \cup {m}
Next == \E m \in Members : Choose(m)
Symmetry == Permutations(Members)

Spec == Init /\ [][Next]_chosen
====
