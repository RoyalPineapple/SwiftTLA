# MCDieHardest reference inputs

`DieHardest.tla`, `MCDieHardest.tla`, and `MCDieHardest.cfg` are unchanged copies from
`tlaplus/Examples@ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`, under `specifications/DieHard`.
The shared `../die-harder/DieHarder.tla` copy uses the same revision.
The license is in `../TLAExamples-LICENSE.md`.

`FiniteSetsExt.tla` is an unchanged copy from
`tlaplus/CommunityModules@9aae8ea1318b3ded4629abdccec2c4754b528d70`, under `modules`.
Its dependencies `Functions.tla` and `Folds.tla` are in `../kvsnap` at the same revision.
The license is in `../kvsnap/CommunityModules-LICENSE`.

The configuration selects `Spec`, `NotSolved`, goal 4, and capacities 5/3 versus 5/3/3.
It retains the default deadlock check and has no state constraint.
The upstream assumptions require single-worker breadth-first search.
A shortest counterexample completes this invariant check, not the infinite reachable graph.
The original source retains its other operators, comments, and assumptions unchanged.
