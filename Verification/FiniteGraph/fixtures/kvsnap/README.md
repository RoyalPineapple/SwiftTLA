# KVsnap reference fixture

`MCKVsnap`, `KVsnap`, `ClientCentric`, and `Util` are unchanged copies from
`tlaplus/Examples` revision `ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`,
under `specifications/KeyValueStore`.

`Functions` and `Folds` are unchanged copies from `tlaplus/CommunityModules`
revision `9aae8ea1318b3ded4629abdccec2c4754b528d70`, under `modules`.
The corresponding licenses are included alongside the sources.

The configuration preserves two keys, three transactions, both invariants,
termination, and TLC's default deadlock check. It removes only symmetry reduction,
which is unsuitable for checking the temporal property and would prevent comparison
of complete unreduced graphs.
