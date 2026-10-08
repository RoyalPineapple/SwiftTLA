# EWD998 reference inputs

`EWD998PCal.tla` and `EWD998PCal.cfg` are unchanged copies from
`tlaplus/Examples@ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`, under
`specifications/ewd998`. `BagsExt.tla` is an unchanged copy from
`tlaplus/CommunityModules@9aae8ea1318b3ded4629abdccec2c4754b528d70`,
under `modules`; its license is in `../kvsnap/CommunityModules-LICENSE`.

The configuration selects `Spec`, `EWD998Spec`, `StateConstraint`, `N = 3`,
and TLC's default deadlock check. `EWD998Spec` compares abstract initial and
next behavior but deliberately excludes abstract fairness, exactly as upstream.

`EWD998ChanID.tla` and `EWD998ChanID.cfg` are unchanged copies from the same
pinned `tlaplus/Examples` revision. The configuration selects five nodes,
`EWD998Safe`, `Max3TokenRounds`, `EWD998ChanSpec`, `EWD998Live`, `View`, and
disables deadlock checking. Their SHA-256 digests are
`c498e5e35a83d84257016fdf4ba359ddb40dbb5f3b2234656e32b419a5499e93`
and `69ec430deca39d7af5e2bfb1f6e43b5c941d29f4362a70048d534a52b8a54146`.
They are reference inputs only; the case is not registered or verified yet.
