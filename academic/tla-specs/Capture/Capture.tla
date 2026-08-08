---- MODULE Capture ----
EXTENDS Integers

VARIABLE phase

TypeOK == phase \in {0,1,2,3}

Init == phase = 0

Configure == phase = 0 /\ phase' = 1
Start     == phase = 1 /\ phase' = 2
Stop      == (phase = 2 \/ phase = 3) /\ phase' = 0
Interrupt == phase = 2 /\ phase' = 3
Resume    == phase = 3 /\ phase' = 2

Next == \/ Configure
        \/ Start
        \/ Stop
        \/ Interrupt
        \/ Resume

Spec == Init /\ [][Next]_phase

ValidPhase == phase >= 0 /\ phase <= 3
NoConfigWhileRunning == (phase # 2 /\ phase # 3) \/ (phase' = phase)

====
