# SwiftTLA completion checklist

The target is the full [DSL contract](../Documentation/DSLDesign.md) and all 78
TLC-marked upstream families at `tlaplus/Examples` revision
`ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`. The 234 published
module/configuration pairs are a baseline, not a cap on source-defined variants.
The [coverage ledger](UpstreamExamples/coverage.json) owns per-criterion, module,
configuration, and evidence status; this checklist owns only the sequence and
admission gates. Do not credit a partial graph, timeout, or unrun configuration.

All 19 DSL criteria have requirement-specific historical acceptance evidence.
The final PR source still needs its own criterion audit and hosted admission.
The full matrix on `a7500dc2` failed because EWD998 N=4 exceeded TLC's
three-hour limit before completing its graph. That result remains incomplete,
not a DSL failure or parity match. The EWD998 family-specific work is deferred
to the next PR; the already represented AsyncTerminationDetection configuration
stays in this PR.

## 1. Close draft PR #394 without expanding its corpus

- [x] Reconcile `a7500dc2`: ordinary CI passed; the unfiltered validation
      matrix failed only because EWD998 N=4 timed out. Do not credit its partial
      graph or reuse that SHA for admission.
- [ ] Keep the 19-criterion DSL contract and existing small acceptance models;
      move the added EWD998 family variants, references, and configurations to
      the follow-up PR. Do not delete the baseline AsyncTerminationDetection
      model or its complete parity case.
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

The `codex/ewd998-family-snapshot` branch retains the EWD998 work removed from
#394. Its historical focused results remain useful diagnostics, but this PR's
ledger credits only AsyncTerminationDetection. Source-defined `*_opts` and
campaign variants still require explicit dispositions and evidence.

- [ ] Restore and finish the deferred EWD998 configurations on both hosted
      paths. The N=4 generated-TLC oracle timed out after three hours with
      119,465,720 distinct states and 11,482,251 states queued. Diagnose
      capacity without shrinking the configuration or calling it complete.
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
