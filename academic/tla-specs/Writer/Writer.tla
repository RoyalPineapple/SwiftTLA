---- MODULE Writer ----
EXTENDS Integers

VARIABLE phase

\* 0=unconfigured 1=configured 2=recording 3=paused 4=completed 5=cancelled
TypeOK == phase \in {0,1,2,3,4,5}

Init == phase = 0

Configure == phase = 0 /\ phase' = 1
Start     == phase = 1 /\ phase' = 2
Write     == phase = 2 /\ UNCHANGED phase
Pause     == phase = 2 /\ phase' = 3
Resume    == phase = 3 /\ phase' = 2
Finish    == phase = 1 /\ phase' = 4
Cancel    == (phase = 2 \/ phase = 3) /\ phase' = 5

Next == \/ Configure \/ Start \/ Write \/ Pause \/ Resume \/ Finish \/ Cancel

Spec == Init /\ [][Next]_phase

ValidPhase == phase >= 0 /\ phase <= 5
NoWriteWithoutRecording == (phase = 2 \/ phase = 3) \/ phase' = phase
====
