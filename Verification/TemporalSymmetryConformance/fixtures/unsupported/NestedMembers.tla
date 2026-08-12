---- MODULE NestedMembers ----
EXTENDS FiniteSets

CONSTANT Members
VARIABLE chosen

Init == chosen = {}
Choose(member) == /\ member \in Members
                  /\ chosen' = chosen \cup {member}
Next == \E member \in Members : Choose(member)
Symmetry == Permutations(Members)
Spec == Init /\ [][Next]_chosen
====
