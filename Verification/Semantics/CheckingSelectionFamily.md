# Checking selection and conditional observation composition

This family follows admitted `2d59884f`. It adds generic selection rules and
checks the actual native scenario and CFG output. Local diagnostics remain
separate from hosted admission. The universal language objective stays open.

## Independent source rules

`CheckingSelectionRule` defines selection by source declaration identity.
Omitting `.checking` selects all declarations, including declarations without
an authored handle. An explicit empty selection selects none. The lowered
rule filters a finite declaration catalog and allocates typed property IDs.
Catalog coverage, handle correspondence and injective allocation are explicit
premises. Native and formal projections preserve selection under those
premises. Injective projections also reflect a changed selection.

The source deadlock relation chooses either the specification default or the
sole explicit override. The lowered rule uses the optional override. The
theorem proves their agreement and uniqueness for zero or one override.
The compiler's existing duplicate-selection rejection remains unchanged.

`CheckingSelectionComposition` defines source reachability from finite paths
through complete labeled edges. Independent source observers quantify over
reachable states. Generated observers collect counterexamples and matches.
Their composition preserves complete initial/edge sets, selected invariant
and reachability verdicts, full supplied failure records and deadlock choice.
Evaluation failure precedes selected deadlock, including when deadlock is
disabled. A constructor bridge supplies the selected sets and flag to an
arbitrary observation, using the catalog and override theorems.

An empty initial set does not produce vacuous checking success. Selected
invariant and reachability results are unavailable without a successful initial
state. Selected deadlock is also unavailable, while unselected deadlock stays
disabled. Initial evaluation failure precedes `noInitialStates`. The empty-set
theorem keeps these inputs in the domain without a nonempty-initial premise.

The observation decision describes abstract failure and deadlock priority.
It does not identify a runtime completion summary or an expectation verdict.
The hosted graph runner also requires a successful initial state. Its separate
failure-only graph limitation remains explicit.

These are conditional rules. The observation theorem requires equal decoded
initial states, labeled edges and failure sets; pointwise-equal pure Boolean
claims; matching property kinds; and complete generated reachability. It
does not prove the traversal kernel. The earlier assignment family preserves
one selected failure and does not establish complete multi-branch failure
sets for this theorem. Predicate-evaluation failures, checking registers,
constraints at excluded boundaries, temporal/refinement semantics, fairness,
symmetry, views, decisive/sampled execution and postconditions remain open
or separately tested. None is removed from the accepted language.

## Measured native output link

The existing canonical owner is
`OrderedAssignmentLoweringTests.orderedIntValidationKeepsInitialOutcomes`.
It retains both original initial-failure forwarding controls and uses one
inline specification with selected and omitted property handles.

An initial diagnostic was mixed: six accepted corruptions and a failed
source-witness assertion. Predicate definitions inside the algorithm body
were outside the structural ordered-Int witness. The corrected test places
the predicates at specification scope and requires the witness before it
continues. Production stayed unchanged for the corrected baseline.

That baseline executed one test with exactly six accepted corruptions:
removed, added and substituted properties; a flipped scenario deadlock flag;
a discarded formal property selection; and a flipped formal deadlock flag.
No setup, compilation, occurrence, positive-output or witness failure occurred.
This establishes a checker blindspot, not wrong production compiler output.

The existing mandatory verifier now receives the complete emitted declaration
array. It decodes each actual scenario constructor's property set and deadlock
literal. It also checks that `render()` forwards the stored checking value and
formal map. The original forwarding checks remain. Its native-only focused
check passed with all six rejecting controls and both original controls.
The test adapter changed to pass all declarations after the baseline; its
bytes are recorded separately. No new public API, model, fixture or injection
hook is introduced. Generated identifier allocation remains a shared premise.

## Measured formal output link

The next mutation-only baseline used the actual root CFG and the unchanged
core checker. Exactly four corruptions escaped: removing or substituting a
source property, changing its directive category, and removing the intrinsic
evaluation invariant. The positive CFG, source witness and native controls
passed. All production inputs remained unchanged during that run.

The existing core checker is generalized as `verifyCheckingConfiguration`.
It compares actual ordered `INVARIANT` and `PROPERTY` directives, intrinsic
checks and deadlock flags against the selected typed configuration. The
separate global source-default requirement still demands `TRUE`. Scenario
overrides may select `FALSE`. The existing owner now includes omitted,
explicit-empty and selected-only scenarios, actual empty/selected CFG
positives, and additional scenario-property/deadlock CFG controls.

`TLCConfiguration.render` invokes that checker before returning CFG bytes.
Its internal throwing signature is propagated through every caller, including
typed PlusCal results. Existing failure results remain failures. No unchecked
compatibility overload remains. The checker accepts the renderer's canonical
single-line directive form; arbitrary authored CFG parsing remains outside
its claim. Behavior, constant/constraint bodies and other directive semantics
are separate boundaries. The expanded CFG focused check passed seven tests in two suites,
including the actual output controls and the configuration selection owner.
The earlier native-only pass remains separate evidence.

## Evidence and remaining boundaries

The current rule and composition modules passed a pinned `--nofp` focused batch
with 24 and 38 obligations. The full current batch passed all 22 rows and
1,616 obligations. All 155 source snapshots and both runner hashes matched
the current inputs. An earlier definition lacked explicit empty-initial
availability. Its passing results remain separate historical evidence.
Earlier failed proof attempts are retained. Their
statements and premises were preserved; named intermediate steps and standard
set extensionality completed the arguments. Static checks passed family
isolation and all five pinned-download controls. Related checks passed 285
tests in 38 suites. They include all 22 prior regression owners and existing
configuration, scenario, assumption, symmetry, fairness, view, refinement,
postcondition, empty-initial and initial-failure owners. All tested input hashes
stayed unchanged during each run. Hosted admission is still pending.

The action batch retains the prior twenty rows in order and inserts the
selection rule before its composition. Ordinary proof receipts also name
`TLCConfiguration`, `SpecCompilation`, `NativeSwiftEmitter+Validation` and
the existing `TLCConfigurationSelectionTests` owner.

Accepted-syntax extraction, source/runtime handle registration, catalog and
property-kind allocation, formal-name freshness, predicate lowering/emission,
checker soundness, native kernels and exhaustive traversal remain owned
premises until independently discharged. Documented Swift behavior and the
pinned external proof tools remain trusted. Actual-output controls and corpus
parity are regressions. They do not establish a complete accepted-program row.
