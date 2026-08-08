---- MODULE Player ----
EXTENDS Integers

VARIABLE phase

\* 0=idle 1=loading 2=ready 3=playing 4=paused 5=finished
TypeOK == phase \in {0,1,2,3,4,5}

Init == phase = 0

Load     == phase = 0 /\ phase' = 1
Ready    == phase = 1 /\ phase' = 2
Play     == (phase = 2 \/ phase = 4) /\ phase' = 3
Pause    == phase = 3 /\ phase' = 4
Seek     == (phase = 2 \/ phase = 3 \/ phase = 4) /\ UNCHANGED phase
Finish   == phase = 3 /\ phase' = 5

Next == \/ Load \/ Ready \/ Play \/ Pause \/ Seek \/ Finish

Spec == Init /\ [][Next]_phase

ValidPhase == phase >= 0 /\ phase <= 5
NoSeekWhileLoading == (phase # 1) \/ UNCHANGED phase
====
