---- MODULE MultipleCollections ----
EXTENDS FiniteSets

CONSTANT Left, Right
VARIABLE chosen

Init == chosen = {}
ChooseLeft(m) == /\ m \in Left
                 /\ chosen' = chosen \cup {m}
ChooseRight(m) == /\ m \in Right
                  /\ chosen' = chosen \cup {m}
Next == (\E m \in Left : ChooseLeft(m)) \/ (\E m \in Right : ChooseRight(m))
Symmetry == {
  [member \in Left \cup Right |-> IF member \in Left THEN left[member] ELSE right[member]] :
    left \in Permutations(Left), right \in Permutations(Right)
}
Spec == Init /\ [][Next]_chosen
====
