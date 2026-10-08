# EWD998PCal reference inputs

`EWD998PCal.tla` and `EWD998PCal.cfg` are unchanged copies from
`tlaplus/Examples@ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`, under
`specifications/ewd998`. `BagsExt.tla` is an unchanged copy from
`tlaplus/CommunityModules@9aae8ea1318b3ded4629abdccec2c4754b528d70`,
under `modules`; its license is in `../kvsnap/CommunityModules-LICENSE`.

The configuration selects `Spec`, `EWD998Spec`, `StateConstraint`, `N = 3`,
and TLC's default deadlock check. `EWD998Spec` compares abstract initial and
next behavior but deliberately excludes abstract fairness, exactly as upstream.
