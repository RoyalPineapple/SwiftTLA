---- MODULE TemporalMatrix ----
EXTENDS Naturals

VARIABLE x

Init == x = 0
A == /\ x = 0
     /\ x' = 2
B == /\ x = 0
     /\ x' = 1
C == /\ x = 1
     /\ x' = 0
Stay == /\ x = 2
        /\ x' = 2
Next == A \/ B \/ C \/ Stay
P == x = 2
Q == x = 1

Spec == Init /\ [][Next]_x
WFSpec == Init /\ [][Next]_x /\ WF_x(A)
SFSpec == Init /\ [][Next]_x /\ SF_x(A)

AlwaysP == []P
EventuallyP == <>P
AlwaysEventuallyP == []<>P
EventuallyAlwaysP == <>[]P
LeadsToPQ == P ~> Q
====
