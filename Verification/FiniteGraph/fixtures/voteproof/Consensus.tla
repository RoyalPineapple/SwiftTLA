---- MODULE Consensus ----
EXTENDS Integers, FiniteSets, Sequences

CONSTANTS Value

VARIABLES chosen

Init == chosen = {}

Next == \E candidate \in Value: (((chosen = {})) = TRUE /\ chosen' = {candidate})


Spec ==
  /\ Init
  /\ [][Next]_chosen

Success == <>(~(Cardinality(chosen) = 0))

====
