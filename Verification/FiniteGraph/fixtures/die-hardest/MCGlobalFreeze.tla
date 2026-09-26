----------------------------- MODULE MCGlobalFreeze -----------------------------
\* Local configuration harness for the unchanged upstream Section 3 operator.
\* Bindings are DieHardest's published running example, not a published CFG.
EXTENDS DieHardest

MCGoal == 2
MCCapacities == <<[j1 |-> 9, j2 |-> 10], [j1 |-> 1, j2 |-> 3]>>
=============================================================================
