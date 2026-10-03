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
unfiltered matrix. This qualifies that matrix, not the unfinished DSL
contract or the full pinned corpus.

The later frozen PR head `d533f10b` passed ordinary CI run `37120573684`
(all five jobs, including Apple-platform examples) and unfiltered validation
run `37120573710` (166 successful jobs, one intentionally skipped diagnostic,
and 165 nonempty retained artifacts). The PR was still draft at that SHA.
Boulanger's complete native graph contained 7,866,982 states and 52,701,220
edges. Native exploration took 938.38 seconds; warm-oracle comparison took
about 178.12 seconds (59.60 native spool, 67.96 TLC spool, 50.55 graph
comparison), about 1,116.50 seconds together. The native job reported
`compare boulanger-0: exact`; the separate cold upstream parity job generated
new TLC evidence and reported `upstream boulanger: exact`. Frozen PR head
`26b3886f` subsequently passed ordinary CI run `37124869258` (all five jobs,
including Apple-platform examples) and unfiltered validation run
`37124869254` (166 successful jobs, one intentionally skipped diagnostic, and
165 distinct, nonempty, unexpired artifacts). The PR remained draft at that
exact head. Local commits after `26b3886f`, including the B-01 legacy
collection cutover, have only focused diagnostics and require their own
source-aligned hosted admission.

Frozen draft PR head `0477d5d3` subsequently passed ordinary CI run
`37129359585` (all five jobs, including Apple-platform examples) and the full,
unfiltered Independent Validation Pipeline run `37129359588` (166 successful
jobs, one intentionally skipped diagnostic, and 165 nonempty, unexpired
artifacts). The PR head still matched this SHA when reconciled. The Boulanger
native run reported the complete 7,866,982-state, 52,701,220-edge graph and
`compare boulanger-0: exact`; native exploration took 586.65 seconds and the
warm-oracle comparison phases about 148.69 seconds, or about 735.34 seconds
combined, below the accepted 1,200-second ceiling. This excludes cold TLC
generation, which ran separately in the upstream parity job and reported
`upstream boulanger: exact`. Local commits after `0477d5d3` close further
symmetry-selection and diagnostic gaps, but still need admission on their own
final pushed SHA. This hosted matrix does not complete the DSL or 78-family
goal.

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
- [x] Bring Boulanger's complete warm-oracle native-plus-comparison path under
      the accepted 1,200-second ceiling without truncating states or edges. This
      is an admission ceiling, not a claim that the runtime is irreducible. On the
      green `767fe50b` SHA, native exploration took 1,044 seconds (1,051
      including its command); warm-oracle comparison took about 246 seconds,
      for about 1,297 seconds together—above that ceiling.
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
      claim. A separate isolated diagnostic measured 300,000 projections of
      Boulanger's initial snapshot at 6.33–6.44 seconds before hoisting
      validated field-name tokens into generated static storage and 5.12–5.25
      seconds afterward, with the model re-expanded between measurements.
      This improves that local projection microcase, not the 1,297-second
      hosted warm-oracle path. The previous hosted profile attributed about
      98 seconds to typed projection; the isolated change still needs a full
      hosted phase measurement and cannot by itself close the runtime gap.
      The later retained `ff35ad76` native profile attributes 300 seconds to
      seen-state lookup, 266 seconds to evidence events (including an estimated
      89 seconds of typed projection and 126 seconds of canonical encoding),
      and 233 seconds to successor generation. A later diagnostic split
      lookup hashing from table probing. Full validation run `37056344757` on
      frozen PR SHA `1b4b5580` passed its unfiltered admission gate: 100 native
      and 53 upstream jobs, 154 nonempty artifacts, and exact Boulanger graph,
      Inv, MutualExclusion, TypeOK, and deadlock evidence. Its native pass took
      1,383 seconds and warm-oracle comparison 242 seconds, about 1,625 together.
      The retained native profile attributes 61 seconds to state hashing, 438
      to dictionary probing/equality, 97 to insertion, 300 to evidence events,
      and 268 to successor generation. The Boulanger job overlapped the large
      CoffeeCan native job, so contention is possible but not established as
      the cause of the regression. Focused profiling run `37064944453` uses
      the same SHA without another native matrix case; compare its phases
      before changing the lookup representation or claiming a speedup. Ordinary
      CI run `37056344561` failed only at the Apple evidence gate's obsolete
      six-test assertion; all seven GeneratedAppleModel and six CameraAdoption
      tests passed. Local commit `eae684ea` fixes that gate, but this SHA is
      not an ordinary-CI-green admission candidate. Local commit `d0db3ba6`
      partitions full state values during binary ingestion and removes the
      second state hash/read pass; all 27 focused comparison tests pass. The
      speedup remains unmeasured until a hosted run of that commit.
      Hosted run `37091564929` on SHA `80a3bc8f` completed Boulanger's
      full 7,866,982-state, 52,701,220-edge native graph in 791.78 seconds
      and compared it exactly with warm generated-TLA TLC evidence in 168.92
      seconds: 960.70 seconds combined. The native profile reports 48.39
      seconds hashing, 124.55 seconds probing, 36.98 seconds inserting,
      264.71 seconds generating successors, and 190.35 seconds emitting
      evidence. Its peak resident size was 3.40 GB. This meets the accepted
      1,200-second performance ceiling on that SHA; it does not admit the
      whole PR. Ordinary CI failed generated-code source-shape assertions,
      and three upstream parity jobs failed while replacing stale cache
      directories. Local commits `5f09a271` and `b5e29170` address those
      failures but need a new source-aligned hosted run after the frozen run
      finishes. Do not pursue a new state-index design on the older 438-second
      probe profile without a renewed measured need.
- [ ] Preserve complete initial states, full state values, labeled edges,
      selected property/deadlock outcomes, and integrity-checked artifacts.
- [ ] Run the exact case first, related regressions second, then ordinary CI and
      full hosted validation on one frozen candidate SHA. Record cold TLC
      generation separately from warm-oracle native checking plus comparison.

### 2. Finish the DSL and native-checking migration

- [ ] Resolve B-01, B-04, B-05, and B-06 in the DSL spec with exact
      signatures, semantics, a positive fixture, and a negative diagnostic.
      Keep the settled B-02 declaration-identity and B-03 expectation contracts.
- [ ] B-04 now has a bound, registered finite-symmetry declaration in `#spec`;
      the formal-core string-named declaration remains only for direct formal
      builders. The focused parser, generated export, and complete native
      symmetry-graph checks pass locally. Scenario-level `usingSymmetry` now
      selects one registered handle for a safety-only TLC configuration;
      foreign, duplicate, and unregistered selections are rejected in focused
      local checks. Remaining fairness/symmetry scope references and hosted
      acceptance are still open. Generated scenarios and plain model exports
      now default to unreduced TLC even when a permutation operator is
      declared; explicit reduction remains available. The exact regression
      and 25 related rendering, configuration, and symmetry checks pass locally.
      A selected temporal claim with symmetry now fails during compilation,
      while an unselected temporal declaration leaves a safety-only scenario
      valid. The regression failed before the guard; 22 related tests pass locally.
      Macro diagnostics now point to the offending symmetry handle rather than
      the model root; that regression failed before the source-map fix and
      passed with 36 related compiler-boundary and scenario tests.
      A model-authored scenario selecting symmetry with a refinement now has a
      focused source-location contract distinct from the formal checker's
      reduction guards; it and 24 related symmetry/diagnostic checks pass
      locally. Hosted B-04 acceptance remains open.
- [x] Settle B-01's fixed-collection replacement design: a typed configuration
      parameter contains stable member IDs; `Each` and typed dictionary state
      use those IDs, while application objects stay outside model state. The
      DSL spec records the positive authoring form and negative boundaries.
      An external consumer now executes and exports this nominal-ID form;
      its focused run and ten related configuration/process tests pass locally.
      That consumer also proves the typed formal action/state projection and
      rejects mixed-population exploration; the two corresponding legacy
      collection tests have been removed after focused local passes.
      A separate external `#spec` consumer confirms that `Each` rejects a
      mutable state-backed population at lowering; its focused test passed
      locally.
      The local cutover removed all `ModelCollection`, `CollectionVar`, and
      `CollectionAction` callers and implementation paths. Focused typed
      consumer, symmetry graph/export, and generated `Sendable` checks pass.
      Hosted parity and the full DSL acceptance audit remain open.
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
      locally. Public positional authoring and parser rejection were closed
      locally later in this migration; hosted acceptance remains pending.
      Four parity fixture files, seven configured-model fixtures, three
      external-consumer fixtures, and the two documentation models now use
      bound declarations. Their guarded local checks passed: 42 focused model
      tests, three external-consumer checks, and five Xcode documentation
      fixture tests. These are local diagnostics, not hosted acceptance.
      Seven more native-checking fixture files now use bound declarations;
      decisive-scenario selectors use binding identities and preserve their
      previous text as display labels. All 19 related guarded tests passed
      locally.
      Eight additional fixture files now use bound identities for mathematical
      integer and sequence domains, initial-state selection, property naming,
      native property keys, function spaces, imported module configurations,
      and symbolic configuration. Their 38 focused guarded tests passed locally.
      Nine generated-machine fixture files covering process locals, sequential
      loops, ordered steps, escaped state and parameter names, reachability,
      selected initial states, scoped invariants, and record-field assignment
      now use bound declarations. Their 38 focused guarded tests, including
      external label diagnostics, passed locally.
      Eleven more fixture files now use bound declarations across Swift
      records, process fairness, breadth-first exploration, sequence index
      conversion and configuration, symbolic records, scenario expectations,
      parser fixtures, local recursion, and enabledness. Their 73 focused
      guarded tests passed locally. The final shared generated-machine
      fixture has also been migrated; all 26 related guarded tests passed,
      including external-consumer compilation. No positional Algorithm or
      Validation calls remain in the shared fixture files; test bodies and
      direct formal-core cases remain to classify and migrate as applicable.
      Five test-body files containing actual `@TLAModel` models now use bound
      algorithm identities; 16 focused guarded actor, generated-machine,
      execution-boundary, and temporal tests passed locally. Parser source
      samples and direct formal-core builder tests remain separately classified.
      Generated formal-union, formal-operator, local-operator, typed-collection,
      imported-module, and compiler-pipeline test models now use bound
      algorithm identities. Their 164 focused guarded tests passed locally;
      direct formal-core builder cases in those files remain unchanged.
      Negative parser samples for fairness, temporal and reachability claims,
      dictionary bindings, state handles, type diagnostics, source authority,
      and compiler-boundary errors now use bound declaration syntax. The
      intended diagnostic and 14 related guarded tests passed locally.
      Bound algorithm identities now cover the typed formal-definition parser
      sample, nested specification macro, multi-binding generated model, and
      structured generated model. Their 40 focused guarded tests passed;
      direct formal-core builders remain explicit comparison oracles.
      Three native-code-generation parser samples now use bound algorithms;
      their focused emission and execution checks passed locally.
      The nested `TLASpec("UnitCounter")` inside a generated refinement model
      now binds and registers `UnitLoop`; both focused refinement checks passed.
      No positional Algorithm or Validation calls remain under `Sources/`.
      Forty-five algorithm parser samples now use bound declarations; their
      62 focused tests passed. The parser now rejects inline, mutable,
      positional-name, and explicit `_name` Algorithm/Validation declarations
      instead of accepting another identity source. Five generated models in
      the builder contract suite were migrated, while direct formal-core
      builders remain package-local fixtures. The targeted identity diagnostic
      and 148 related parser/builder tests passed; after package-scoping the
      positional constructors, the targeted diagnostic passed again with the
      entire local package compiling through the guarded wrapper, and all 148
      related parser/builder tests passed again. This is local diagnostic
      evidence, not hosted acceptance.
      An isolated local change now preserves the Swift identity of a binding
      named `algorithm` while rendering a collision-free PlusCal name, including
      when `_algorithm` is an authored state variable. The exact regression and
      161 related parser, builder, and renderer tests passed locally; hosted
      acceptance for this change is pending.
      Audit remaining package-local positional formal-core fixtures and
      scenario references; do not expose them as application authoring.
      B-02 now explicitly leaves inline control statements anonymous while
      requiring stable bindings for named declarations; the exact rejection
      and nine related compiler-boundary diagnostics passed locally. Recheck
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
      simply be deleted without equivalent behavioral proof. VoteProof's
      corpus execution test now checks generated initial values, typed ballot
      choices, invariants, and ambiguity directly; its compiled-runtime oracle
      and duplicate rendering-suite witness were removed in local commit
      `097a1092`. The focused execution and rendering suites pass locally;
      hosted acceptance remains pending.
      Three collection fixtures now use generated independent `Do` steps and
      native exploration instead of formal `ModelChecker` calls. Their complete
      small labeled graphs, invariant/deadlock outcomes, and rendered collection
      operations pass focused local checks; the formal value round-trip remains
      a separate serialization-boundary test. This does not credit AC-12 or
      independent TLC parity.
      The duplicated formal function-update models have likewise been replaced
      by one generated typed-dictionary model. Its initial action choices,
      complete four-state/four-edge labeled graph, and deadlock pass locally;
      the distinct formal expression-lowering suite still passes. No hosted
      parity claim follows from these focused tests.
- [ ] Close AC-13 by removing replaced spellings, duplicate configuration,
      obsolete callers, compatibility aliases, and stale documentation. The
      legacy `CollectionVarType` field had no effect on model behavior; it was
      only copied through declarations and included in the compilation
      fingerprint. Its public type, field plumbing, and test-only identity
      variant have been removed locally. The 80-test compiler-pipeline suite
      and static guard pass; this still needs hosted admission on a new SHA.
- [ ] Close AC-14 with generated-machine identity by default and sound,
      explicit symmetry admission plus complete TLC-orbit comparison.
- [ ] Close AC-17 through AC-19 with direct Swift value types, stable
      declaration-derived names, and compile-time type resolution/diagnostics.
      Ordinary `[Element]()` and `[Element]([...])` array constructors now
      resolve in `#spec` through the same type resolver as `Array<Element>`.
      The generated array fixture failed before this parser fix and its four
      related tests pass locally afterward. The generated function-space
      membership fixture now uses `#spec`, `Do`, and ordinary Swift `Set`
      ranges rather than formal `Var`/`Action` declarations; its generated
      large-domain and failure contract plus ten neighboring tests pass
      locally at `624b8aa1`. `Where` now accepts ordinary Swift sets without
      changing their type; the generated positive and empty initial-domain
      regressions failed to compile before the fix and nine related tests
      pass locally. Hosted acceptance remains open.
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
