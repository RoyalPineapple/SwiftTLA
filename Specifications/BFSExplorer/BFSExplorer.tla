---- MODULE BFSExplorer ----
EXTENDS Naturals, FiniteSets, Sequences

(***************************************************************************)
(* BFS state exploration of a directed graph.                             *)
(* Models: queue processing, deduplication, invariant checking, deadlock. *)
(***************************************************************************)

CONSTANT MaxState   \* Graph has states 0..MaxState-1
CONSTANT MaxExplore \* Stop after this many states

ASSUME MaxState > 0 /\ MaxExplore > 0

\* Abstract system under test: each state transitions to state+1 (linear)
States == 0 .. (MaxState - 1)

\* The BFS explorer
VARIABLES 
    q,           \* queue as a set (order doesn't matter for correctness)
    visited,     \* canonical states seen
    explored,    \* states fully processed
    ok           \* TRUE while running, FALSE if invariant violated

Init ==
    /\ q = {0}
    /\ visited = {0}
    /\ explored = {}
    /\ ok = TRUE

\* Process one state from the queue
Next ==
    /\ q # {}
    /\ LET s = CHOOSE x \in q : TRUE  \* pick any state
       IN  \* Check bound
           /\ Cardinality(explored) < MaxExplore
           \* Transition: s -> s+1 (within bounds)
           /\ LET succ = {s+1} \cap States
              IN  /\ q' = (q \ {s}) \cup (succ \ visited)
                  /\ visited' = visited \cup succ
                  /\ explored' = explored \cup {s}
                  /\ ok' = ok

Spec == Init /\ [][Next]_<<q, visited, explored, ok>>

(***************************************************************************)
(* Correctness properties                                                *)
(***************************************************************************)

\* Type invariant
TypeOK ==
    /\ q \subseteq States
    /\ visited \subseteq States
    /\ explored \subseteq States
    /\ explored \subseteq visited

\* Every visited state is reachable from 0
ReachableClosure ==
    explored \subseteq { s \in States : s \leq Cardinality(explored) }

\* No duplicate work
NoDuplicates ==
    explored \cap visited = explored   \* explored subset of visited

\* Bound enforcement
BoundOK ==
    Cardinality(explored) \leq MaxExplore

\* If queue is empty and ok, all states reachable within bound are explored
Completion ==
    (q = {} /\ ok) => 
        LET max = IF Cardinality(explored) < MaxState 
                  THEN Cardinality(explored) - 1 
                  ELSE MaxState - 1
        IN explored = 0 .. max

====
