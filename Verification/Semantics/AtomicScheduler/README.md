# From authored assignments to the action returned by lower

For a finite block of root assignments with literal/read/add right-hand sides and a valid allocator, the scheduler starts with empty pending writes and replacements. Each assignment adds one LET around the recursively returned suffix. A later write to the same target replaces its pending final write while preserving both LET evaluations.

For the standalone `Do` route, `ActualReturnedBlockSuppliesTheCompleteAssignmentOutcome` uses the same scheduler return to compute the action returned by `lowerAtomicStep`. At every authored index the returned definition has that row’s fresh binder and substituted RHS, and its body is the next definition or the terminal action. `StandaloneBlockAction` takes the authored statements, allocator and key ordering. Its traversal depth comes from the number of authored writes. The proof uses the checked caller and LET branches under a reviewed interpretation of ordinary Swift returns, optionals and collections. [Parent theorem](AtomicSchedulerFiniteBlock.tla#L774)

The same rows supply the abstract first-overflow and preceding-bindings history. Frame completion, typed operand resolution, and the meaning of the configured TLA for arbitrary blocks still need to be linked to this returned action.

## Reproduce the focused checks

Run from the repository root with the pinned proof tools. Set `PACKET` to the directory containing `case/` and `proof-inputs/` from a local `proof-prepare` run with `ordered-copy-actions`. To recreate that packet, the wrapper takes a new directory under the common Git directory's `swifttla-proof-evidence/`, the checked `SwiftTLAInitialFailureProof.tla` for the source revision, and `ordered-copy-actions`. The checked proof is also in the matching hosted initial-failure artifact under `case/generated-tla/`.

```sh
proof=Verification/Semantics/AtomicScheduler
body="$proof/AtomicSchedulerFiniteBlock.tla"
inputs=$(mktemp -d)/scheduler
python3 "$proof/prepare-inputs.py" "$inputs"

scripts/local-validation.sh proof-step "$PACKET" 624 652 "$body" "$inputs/compiler.bin" "$inputs/caller.bin" \
    --also 654 714 "$body" "$inputs/compiler.bin" "$inputs/caller.bin"
scripts/local-validation.sh proof-step "$PACKET" 774 839 "$body" "$inputs/compiler.bin" "$inputs/caller.bin"
```

The input helper reproduces the byte containers checked at `06c0987ea7d4ecc43b17711c53b1653d30af6410`. It compares the four compiler files addressed by the proofs with the checkout and verifies both whole-container SHA-256 digests. Other compiler files retained after the addressed ranges come from that Git revision.

For the negative control, only the argument changes from `lower(scheduled, …)` to `lower(step.model.statements, …)`. The original forwarding theorem fails on that input. A second check positively identifies the authored operand and proves it differs from the scheduler return whenever the two bodies differ.

```sh
scripts/local-validation.sh proof-step "$PACKET" 68 80 "$proof/AtomicSchedulerFiniteBlock.imports/AtomicSchedulerHandoff.tla" \
    "$inputs/authored-argument.bin" "$inputs/caller.bin"  # expected FOCUSED_NOT_PROVED
scripts/local-validation.sh proof-step "$PACKET" 69 83 "$proof/WrongHandoffExplanation.tla" \
    "$inputs/authored-argument.bin" "$inputs/caller.bin"  # expected focused pass
```

## Retained scheduler handoff results

| Checked selection | Obligations discharged | Proof log SHA-256 |
| --- | ---: | --- |
| One certified edge matches the recursive call and return | 37 | `ed93f0d637e592411ac58adbe08662df5c18dcf73e632b54e6a732ad69922006` |
| Certified trace matches the computed scheduler return | 97 | `f393cb84d2ff1f5e6521ed19d0a4794c52d639f2c591bd7ffdef589343ad9fa9` |
| Complete assignment outcome for the body passed to lower | 33 | `72446d1c25cda4c06a28641645e8c2240c8108d21efc0d6409d1840b7dcb5151` |

All three checks used parent module SHA-256 `b3fcbff74abb829f42bcc83aba1d4edcfebff37cfe1e8a9735478e246e8517f5`. The runner records `FOCUSED_PASS_DEPENDENCIES_UNCHECKED`: the selected theorem passed and the imported theorem bodies have separate proof obligations. Hosted admission and preservation through typechecking or either backend remain separate.
