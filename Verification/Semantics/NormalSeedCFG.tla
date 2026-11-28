---- MODULE NormalSeedCFG ----
EXTENDS CompilerInputPageBlock1, TLAPS

\* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
\* The seed's normal TLC configuration selects Spec and requests deadlock checking.
SeedCFG == <<83, 80, 69, 67, 73, 70, 73, 67, 65, 84, 73, 79, 78, 32, 83, 112, 101, 99, 10, 67, 72, 69, 67, 75, 95, 68, 69, 65, 68, 76, 79, 67, 75, 32, 84, 82, 85, 69, 10>>
ActualCFG == [i \in 1..CompilerInputSize |-> CompilerInputByte[i - 1]]

THEOREM NormalCFGIsTheSpecAndDeadlockSelection ==
    ActualCFG = SeedCFG
    PROOF
    <1>len. DOMAIN ActualCFG = DOMAIN SeedCFG BY SMT DEF ActualCFG, SeedCFG, CompilerInputSize
    <1>bytes. \A i \in DOMAIN SeedCFG : ActualCFG[i] = SeedCFG[i]
        BY ONLY CompilerInputPageBlock1AtFileOffsets, SMT DEF ActualCFG, SeedCFG, CompilerInputSize
    <1>. QED BY <1>len, <1>bytes, SMT DEF ActualCFG, SeedCFG

====
