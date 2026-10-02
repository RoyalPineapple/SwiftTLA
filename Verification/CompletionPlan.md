# SwiftTLA completion plan

This is an execution checklist, not a second DSL specification or a substitute
for evidence. [DSLDesign.md](../Documentation/DSLDesign.md) defines the language
contract. [coverage.json](UpstreamExamples/coverage.json) is the authoritative
configuration-by-configuration ledger. The target is all 78 TLC-marked families
at upstream revision `ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`, including
applicable modules, variants, and configurations. The 234 published
module/configuration pairs are a baseline, not a cap on source-defined variants.

## Baseline and admission rule

At Swift SHA `767fe50bf6108ec39f7b19c35e4badd44735c364`, the ledger records
19/78 complete families and 44/234 hosted-matched published configurations.
Twelve DSL criteria are marked implemented, not finally accepted; seven are
marked missing. Ordinary CI run `37004522387` and the full Independent Validation
Pipeline run `37004522298` passed on this exact SHA. The latter passed 100 native
and 53 upstream parity jobs, retained 154 nonempty artifacts, and admitted the
unfiltered matrix. This qualifies the current matrix, not the unfinished DSL
contract or the full pinned corpus.

Only the full, unfiltered hosted matrix and ordinary CI on the same final pushed
SHA can establish final admission. Focused diagnostics guide development but
never confer family or final-revision credit. Create PRs in draft mode and keep
them draft while their declared scope is unfinished. PR #394 may close the DSL
migration and its existing matrix before all 78 families are complete; the
remaining families must then be completed in follow-up PRs. Do not weaken
models or checks to fit the implementation.

## Sequence

Keep one candidate SHA and one active family at a time. The immediate queue is:

1. Remove the measured Boulanger runtime gap while preserving complete evidence.
2. Finish the native-checking migration, then close the remaining DSL contract
   gaps and PR #394's existing configurations.
3. Complete the next whole family and repeat. Dijkstra is a candidate, not
   pre-credited work.

### 1. Close the current candidate and performance gap

- [x] Reconcile the `767fe50b` hosted runs, required jobs and retained
      artifacts against the exact draft PR head. Both independent paths and
      ordinary CI passed; no result was inferred from an earlier SHA.
- [ ] Bring Boulanger's complete warm-oracle native-plus-comparison path to an
      acceptable measured runtime without truncating states or edges. On the
      green `767fe50b` SHA, native exploration took 1,044 seconds (1,051
      including its command); warm-oracle comparison took about 246 seconds,
      for about 1,297 seconds together—above the accepted 919-second reference.
      Generated-TLA TLC evidence was restored from cache for that native job;
      the separate upstream parity job spent about 21.5 minutes generating
      cold TLC evidence before comparison. The
      measured hot paths are seen-state lookup, evidence projection/encoding,
      and event handling. The retained binary evidence has 8,915,871 exact
      self-loop edges out of 52,701,220 (16.9%); a self-loop lookup shortcut
      alone cannot close the gap and was not promoted. A complete scan found
      zero duplicate `(source, action, target)` records, so edge deduplication
      cannot reduce this case either. An isolated debug diagnostic capped at
      100,000 states took 19.64 seconds before and 19.15 seconds with cached
      per-field snapshot hashes; the 2.5% gain did not justify that extra state
      storage, so the experiment was reverted. This is not a full-run speedup
      claim. Measure each phase again before claiming improvement.
- [ ] Preserve complete initial states, full state values, labeled edges,
      selected property/deadlock outcomes, and integrity-checked artifacts.
- [ ] Run the exact case first, related regressions second, then ordinary CI and
      full hosted validation on one frozen candidate SHA. Record cold TLC
      generation separately from warm-oracle native checking plus comparison.

### 2. Finish the DSL and native-checking migration

- [ ] Resolve B-01, B-02, B-04, B-05, and B-06 in the DSL spec with exact
      signatures, semantics, a positive fixture, and a negative diagnostic.
      Keep the settled B-03 expectation syntax and semantics.
- [x] Settle B-02 identity for `Algorithm` and `Validation`: each requires an
      immutable `let` binding, registered by reference; a display label never
      supplies identity. The parser and `#spec` rewrite support this form.
      Focused parser rejection tests and an executing external consumer passed
      locally; these are diagnostic evidence, not hosted acceptance.
- [ ] Finish B-02: optional labels now reach compiled algorithm descriptions
      and generated stateful and assumption-only scenarios; focused local
      checks passed, but hosted acceptance remains pending. All five canonical
      corpus models now use bound algorithm and validation identities, with
      their published names preserved in focused local rendering checks. The
      configured Counter uses binding identities and separate display labels;
      its focused checking and scenario-admission regressions passed locally.
      DSL spec examples and the generated-machine guide now show bound
      declarations; the matching guide fixture passed guarded Xcode tests.
      The Apple-platform and SwiftTLADemos algorithm examples now use bound
      identities; their focused generated-machine tests passed locally.
      The seven DieHard-family validation declarations now use bound identities
      while retaining their published configuration names; all 11 selected
      DieHard-family checking tests passed through the guarded local wrapper.
      All remaining upstream-example Algorithm and Validation declarations now
      use bound identities. Five scenario selectors whose names could not be
      reused as distinct Swift bindings retain their former text as display
      labels, with manifest and coverage selectors updated but case IDs and
      pinned upstream inputs unchanged. A guarded 17-test batch covering the
      affected teaching, Dining, HourClock2, Prisoner, Chang-Roberts, and
      inventory contracts passed locally; hosted parity for these edits is
      still pending.
      The remaining 66 direct `#spec` Algorithm and Validation declarations in
      validation models and conformance fixtures now use bound identities;
      presentation-only labels retain readable scenario titles. A guarded
      52-test batch covering selected checks, configured processes, records,
      dictionaries, temporal checks, refinement, and binary evidence passed
      locally. The nested formal-core `TLASpec("UnitCounter")` algorithm still
      uses its explicit formal name; public positional authoring and parser
      rejection are not complete.
      Migrate every remaining positional-name caller and scenario reference,
      remove the old public forms, and settle the remaining
      declaration/anonymous rules. Recheck
      generated TLA and native scenario identity on the migrated matrix.
- [ ] Audit AC-01 through AC-19 against each criterion's full acceptance text.
      Existing `implemented` labels are not acceptance evidence by themselves.
- [ ] Close AC-09 with separate native/TLC invariant, deadlock, termination,
      stuttering, and temporal-cycle cases, including legitimate early results.
- [ ] Close AC-12 by moving every application and Swift-checking caller to the
      generated transitions and predicates. Remove interpreter/compiled-runtime
      checking paths only after their behavior is covered; keep formal parsing
      or export boundaries only with an explicit non-checking justification.
      The remaining source-owned paths include `ModelChecker`,
      `RefinementChecker`, and `CompiledSpecification+TemporalAnalysis`; their
      formal-core test callers must migrate to generated-machine contracts, not
      simply be deleted without equivalent behavioral proof.
- [ ] Close AC-13 by removing replaced spellings, duplicate configuration,
      obsolete callers, compatibility aliases, and stale documentation.
- [ ] Close AC-14 with generated-machine identity by default and sound,
      explicit symmetry admission plus complete TLC-orbit comparison.
- [ ] Close AC-17 through AC-19 with direct Swift value types, stable
      declaration-derived names, and compile-time type resolution/diagnostics.
- [ ] Confirm the four required end-to-end model classes (Counter, mutual
      exclusion, puzzle, distributed protocol) each execute as an application,
      explore the same generated transitions, validate separately with TLC,
      and have no superseded caller path.
- [ ] Confirm one resolved typed model feeds generated native Swift and
      equivalent TLA+ export; types and declaration identities survive until
      serialization. Native validation must work without TLC or parity tools.
- [ ] Merge PR #394 only after all 19 criteria, replacement/deletion work, and
      all configurations already in that PR pass ordinary CI and both parity
      paths on one final SHA. This is a PR gate, not completion of the 78-family
      goal.

### 3. Complete the pinned corpus, one whole family at a time

- [ ] For the next family, inspect its pinned modules and every published
      configuration, then enumerate source-defined variants and selected checks.
- [ ] Identify concrete DSL/compiler/checker gaps by upstream file, operator,
      configuration, and smallest reproducer. Implement the shared capability
      once without introducing model-specific semantics into validation tooling.
- [ ] Author all family scenarios in SwiftTLA; derive validation selection and
      settings from the model, rather than a second hand-maintained registry.
- [ ] For every applicable configuration, compare generated TLA against pinned
      upstream TLC and generated Swift against generated-TLA TLC. For exhaustive
      runs compare complete initial states, full state-labeled/action-labeled
      graphs, selected properties and deadlock. For decisive early results,
      compare verdict and replayable witness without claiming graph equality.
- [ ] Resolve every helper/module disposition and remove the family's legacy
      implementation. Update `coverage.json` only with source-bound, retained
      evidence. A partial family remains incomplete.
- [ ] Freeze one SHA, pass ordinary CI and the full hosted matrix, then start
      the next family. Use one complete family per follow-up PR where practical;
      keep unusually large partial families visibly incomplete. The family
      worklist and individual configuration status are the 78 records in
      `coverage.json`; do not copy their status into a competing checklist.

The next family should be selected only after the current candidate is
reconciled. Dijkstra's mutual exclusion algorithm is a candidate because it has
two published configurations and an existing partial port, but neither
configuration has hosted-match credit. Inspect its 3-process liveness and
4-process safety variants before committing to it; if a measured shared blocker
has higher leverage, finish that blocker first.

## Final audit

- [ ] All 19 DSL criteria have requirement-specific implementation and
      acceptance evidence; all five open B-decisions are resolved; all four
      end-to-end model classes satisfy their complete contracts.
- [ ] All 78 families have every applicable configuration and variant verified,
      all modules dispositioned, and legacy cleanup complete. No missing,
      unsupported, timed-out, or truncated result is credited.
- [ ] Generated Swift and TLA+ derive from the same resolved typed model; all
      native checking uses generated transitions. Product code has no dependency
      on TLC, upstream examples, CI, or the parity harness.
- [ ] Replaced paths and documentation are migrated/deleted, the worktree is
      clean, and ordinary CI plus full independent validation are green with
      retained evidence on the final pushed SHA.
