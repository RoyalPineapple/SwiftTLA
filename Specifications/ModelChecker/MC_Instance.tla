---- MODULE MC_Instance ----
EXTENDS ModelCheckerProof

(* A simple 4-state spec: 0 → 1 → 2 → 3 (terminal at 3) *)
StateCount == 4
MaxStates  == 10

Transitions == [
    s \in {0} |-> {1},
    s \in {1} |-> {2},
    s \in {2} |-> {3}
]

InvariantFn == [
    s \in {0,1,2,3} |-> TRUE
]

Terminal == {3}

====
