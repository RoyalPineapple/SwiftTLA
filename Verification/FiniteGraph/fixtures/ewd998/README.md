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
The five-node case has focused hosted parity on its complete configured `VIEW`
graph at `c1c4ee49179592fa50751e045bfdbaaa6f829060`; this is not a
full clock-bearing graph or final-revision admission claim.

`EWD998ChanTrace.tla`, `.cfg`, and `.ndjson` are unchanged pinned upstream
inputs. The reference diagnostic binds the 654-event log through the `JSON`
environment variable and uses the separately pinned CommunityModules release
and source closure. Hosted run `37894703890` on SHA `716a7783` satisfied
`TraceAccepted` and retained artifact `11601000946`. Its instrumented copy
printed TLC's chosen `TraceLog`; the diagnostic mapped every record back to a
source line and checked vector-clock order. The resulting
`EWD998ChanTrace.selected-order.json` contains that JSON payload, followed by
a file-terminating newline. The hosted payload is pinned by SHA-256
`b728a7eac858354dc10d2bc4616ba68fcca724ca141a1890e5bf0c5dec6af6eb`.
The pinned `VectorClocks.tla`
(`69cc7f09a0b1048495843778ba34afd3e1cb11881cd8e1ce7b725b376aeb9a6a`)
uses `CHOOSE` over valid permutations, so a locally chosen topological order
would not establish TLC's selected `TraceLog`. This reference result does not
compare a generated Swift machine or generated TLA, so it does not complete
trace parity.

`EWD998ChanID_shiviz.tla` and `.cfg` are also byte-for-byte pinned upstream
inputs. In hosted run `37894703890`, pinned TLC exited 255 before exploration:
`MCInit` does not assign the base model's `passes` variable. The local
reference diagnostic now classifies that source-invalid outcome, but neither
the diagnostic correction nor a Swift port has hosted parity evidence.

`EWD998ChanID_export.tla` and `.cfg` are byte-for-byte pinned at SHA-256
`638f814c422250d6debe1209419971b66ead59c8aa8aca4a2efcc29feb379985`
and `a02a94fce512a1c7f8c47f0c35bbad7813dfedbafec7212d2404c585541b078a`.
Their selected `PostInv` can execute an HTTP POST. The reference-only diagnostic
stages the exact source and configuration but gives TLC a `PATH` containing only
a local `curl` interceptor. The interceptor accepts only the published command,
retains its trace payload, and performs no network request. Hosted run
`37894703890` exited 255 on the same incomplete `MCInit` before a POST was
attempted. The local diagnostic correction classifies this source-invalid
outcome; it is not hosted parity for a Swift implementation.
