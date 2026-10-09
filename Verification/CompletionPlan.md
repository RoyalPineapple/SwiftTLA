# SwiftTLA completion checklist

The target is the full [DSL contract](../Documentation/DSLDesign.md) and all 78
TLC-marked upstream families at `tlaplus/Examples` revision
`ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`. The 234 published
module/configuration pairs are a baseline, not a cap on source-defined variants.
The [coverage ledger](UpstreamExamples/coverage.json) owns per-criterion, module,
configuration, and evidence status; this checklist owns only the sequence and
admission gates. Do not credit a partial graph, timeout, or unrun configuration.

As recorded in the ledger on 2026-10-08, all 19 DSL criteria are marked
implemented with requirement-specific historical acceptance evidence. AC-13 was
accepted on frozen PR SHA `852295bc`, with all five ordinary CI jobs and the
unfiltered validation matrix green. Sixty of the 234 published configurations
have historical hosted-match evidence. The later PR head still needs its own
admission result; none of these counts completes the 78-family corpus.

## 1. Close draft PR #394 without expanding its corpus

- [ ] Reconcile the frozen candidate's ordinary CI and full, unfiltered
      Independent Validation Pipeline once both are terminal. Confirm the PR
      head, source/tool/input pins, every required job, and nonempty retained
      artifacts. The existing heartbeat reports the terminal result; do not
      restart or compete with the run while it is active.
- [ ] Fix only a demonstrated failure. For each fix, run the exact focused
      check through `scripts/local-validation.sh`, then related focused checks.
      Local diagnostics never substitute for hosted evidence.
- [ ] Audit all 19 criteria against the final source, including compiler
      diagnostics, `#spec` identity and configuration, generated native
      checking, equivalent TLA+ export, and removal of replaced authoring and
      runtime paths. AC-13 needs explicit final-head acceptance evidence.
- [ ] Freeze one final pushed SHA. Ordinary CI, including Apple-platform
      examples, and the full unfiltered validation matrix must pass on that
      same SHA with retained evidence for both independent comparison paths.
- [ ] Merge PR #394 only after that gate. This completes its declared DSL and
      existing-matrix scope, **not** the 78-family corpus. Keep the PR draft
      until it is ready for that decision.

## 2. Finish EWD998 as one family

Use the separate EWD998 worktree while PR #394 is frozen; do not push a
competing candidate during its admission run. The ledger currently records
three hosted-matched, three implemented-but-unverified, and five missing
published EWD998 configurations. Source-defined `*_opts` and campaign variants
also require explicit dispositions and evidence.

- [ ] Finish the already implemented `ewd998-0`, `ewd998-small-0`, and
      `ewd998-chan-0` configurations on both hosted paths. The N=4 graph's
      reported scale is a capacity issue to measure, not permission to shrink
      the configuration or call a timeout complete.
- [ ] For `EWD998ChanTrace`, bind the exact pinned TLA/CFG, implementation log,
      and CommunityModules closure to a hosted TLC run. Retain a TLC-selected
      causal ordering, validate it against the complete raw events, and make
      the generated Swift machine and generated TLA perform the same trace
      check. Compare the selected postcondition and configured level-sensitive
      view; a base channel-graph match does not prove trace acceptance.
- [ ] Implement the export and shiviz configurations from their exact source
      contracts. Establish the pinned shiviz result before translating its
      incomplete initialization. Never perform the export configuration's
      external HTTP POST unnoticed; an explicit safe execution contract must
      preserve the configured observable outcome.
- [ ] Implement sampled smoke and nested-TLC/CSV campaign outcomes as their
      published checking modes, without calling sampled witnesses complete
      graph parity. Disposition the source-defined `*_opts` variants as well.
- [ ] Audit every EWD998 helper/module, remove superseded implementations,
      then require ordinary CI and the full validation matrix on one frozen
      SHA before marking the family complete. A configured `VIEW` compares the
      complete *view-identified* graph; it does not prove full-state equality.

## 3. Repeat for the remaining families

- [ ] Choose one incomplete family from the ledger. Inventory every pinned
      module, published configuration, source-defined variant, and selected
      property/deadlock/fairness setting before implementation.
- [ ] Implement only DSL capabilities required by a named case. The product
      owns DSL semantics, generated Swift and TLA+, and native checking;
      validation infrastructure consumes those outputs and may not supply
      transition or property semantics.
- [ ] Complete all applicable family configurations. For exhaustive cases,
      compare complete initial states, full state-labeled/action-labeled
      graphs, selected property and deadlock verdicts, and provenance on both
      paths: generated TLA versus pinned upstream TLC, then generated Swift
      versus generated-TLA TLC. For decisive early results, compare verdicts
      and replayable witnesses without claiming graph equality.
- [ ] Perform a Ponytail review and cleanliness pass: remove obsolete paths,
      duplicate witnesses, compatibility shims, and stale evidence. Freeze one
      SHA and obtain full hosted admission before counting the family done.
      Prefer one complete family per follow-up PR; an unusually large split
      remains visibly partial until its last configuration passes.

## Final audit

- [ ] All 19 DSL criteria have final-source acceptance evidence, all 78
      families have complete module and variant dispositions, and every
      applicable configuration has exact hosted evidence. No missing,
      unsupported, timed-out, or truncated result is credited.
- [ ] One resolved typed model feeds generated native Swift and TLA+ export.
      Native checking uses generated transitions and works without TLC, the
      upstream repository, CI, or the parity harness.
- [ ] Replaced code and documentation are removed or migrated; the final
      pushed SHA passes ordinary CI and full independent validation, and the
      worktree is clean.
