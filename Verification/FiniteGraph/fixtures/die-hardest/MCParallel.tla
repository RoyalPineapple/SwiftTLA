----------------------------- MODULE MCParallel -----------------------------
\* Local harness for the unchanged upstream Sections 1 and 2 operators.
\* These bindings are DieHardest's running example, not a published CFG.
EXTENDS DieHardest

MCGoal == 2
MCCapacities == <<[j1 |-> 9, j2 |-> 10], [j1 |-> 1, j2 |-> 3]>>
=============================================================================
