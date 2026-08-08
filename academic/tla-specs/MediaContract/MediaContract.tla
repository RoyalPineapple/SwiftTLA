---- MODULE MediaContract ----
EXTENDS Integers

VARIABLES cPhase, wPhase, pPhase

\* Capture: 0=unconfigured 1=configured 2=running 3=interrupted
\* Writer:  0=unconfigured 1=configured 2=recording 3=paused 4=completed 5=cancelled
\* Player:  0=idle 1=loading 2=ready 3=playing 4=paused 5=finished

TypeOK == cPhase \in {0,1,2,3} /\ wPhase \in {0,1,2,3,4,5} /\ pPhase \in {0,1,2,3,4,5}

Init == cPhase = 0 /\ wPhase = 0 /\ pPhase = 0

\* --- Capture actions ---
CConfigure == cPhase = 0 /\ cPhase' = 1 /\ UNCHANGED <<wPhase, pPhase>>
CStart     == cPhase = 1 /\ cPhase' = 2 /\ UNCHANGED <<wPhase, pPhase>>
CStop      == (cPhase = 2 \/ cPhase = 3) /\ (wPhase # 2 /\ wPhase # 3) /\ cPhase' = 0 /\ UNCHANGED <<wPhase, pPhase>>
CInterrupt == cPhase = 2 /\ (wPhase # 2 /\ wPhase # 3) /\ cPhase' = 3 /\ UNCHANGED <<wPhase, pPhase>>
CResume    == cPhase = 3 /\ cPhase' = 2 /\ UNCHANGED <<wPhase, pPhase>>

\* --- Writer actions ---
WConfigure == wPhase = 0 /\ wPhase' = 1 /\ UNCHANGED <<cPhase, pPhase>>
WStart     == wPhase = 1 /\ cPhase = 2 /\ wPhase' = 2 /\ UNCHANGED <<cPhase, pPhase>>
WWrite     == wPhase = 2 /\ UNCHANGED <<cPhase, wPhase, pPhase>>
WPause     == wPhase = 2 /\ wPhase' = 3 /\ UNCHANGED <<cPhase, pPhase>>
WResume    == wPhase = 3 /\ wPhase' = 2 /\ UNCHANGED <<cPhase, pPhase>>
WFinish    == wPhase = 1 /\ wPhase' = 4 /\ UNCHANGED <<cPhase, pPhase>>
WCancel    == (wPhase = 2 \/ wPhase = 3) /\ wPhase' = 5 /\ UNCHANGED <<cPhase, pPhase>>

\* --- Player actions ---
PLoad      == pPhase = 0 /\ pPhase' = 1 /\ UNCHANGED <<cPhase, wPhase>>
PReady     == pPhase = 1 /\ pPhase' = 2 /\ UNCHANGED <<cPhase, wPhase>>
PPlay      == (pPhase = 2 \/ pPhase = 4) /\ wPhase = 4 /\ pPhase' = 3 /\ UNCHANGED <<cPhase, wPhase>>
PPause     == pPhase = 3 /\ pPhase' = 4 /\ UNCHANGED <<cPhase, wPhase>>
PSeek      == (pPhase = 2 \/ pPhase = 3 \/ pPhase = 4) /\ UNCHANGED <<cPhase, wPhase, pPhase>>
PFinish    == pPhase = 3 /\ pPhase' = 5 /\ UNCHANGED <<cPhase, wPhase>>

Next == \/ CConfigure \/ CStart \/ CStop \/ CInterrupt \/ CResume
        \/ WConfigure \/ WStart \/ WWrite \/ WPause \/ WResume \/ WFinish \/ WCancel
        \/ PLoad \/ PReady \/ PPlay \/ PPause \/ PSeek \/ PFinish

Spec == Init /\ [][Next]_<<cPhase, wPhase, pPhase>>

\* --- Cross-actor invariants ---
WriterRequiresCapture == (wPhase = 2 \/ wPhase = 3) => (cPhase = 2)
PlayerRequiresWriter  == (pPhase = 3) => (wPhase = 4)
====
