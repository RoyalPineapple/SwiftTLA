# SwiftLint zero-new-violations gate

Run the gate from the repository root:

```bash
./scripts/lint-zero-new.sh
```

The gate runs SwiftLint in strict mode over authored Swift sources. It excludes only nested build products, package-manager/checkouts, and generated trees through [`.swiftlint.yml`](../.swiftlint.yml); product and test sources remain in scope.

`.swiftlint-baseline.json` records 299 exact legacy findings captured on 2026-08-09 with SwiftLint 0.65.0. Each baseline entry contains its rule, file, line, character, and source text. The file uses a checkout-root placeholder, which the gate materializes to the current physical checkout path before passing it to SwiftLint, so the baseline works in local clones and CI without hiding new locations.

The capture compared the current symmetric-collections working tree with pre-feature `46c782b`: the pre-feature scan reported 318 authored-source findings, and the repaired working tree reported 299. A changed-line audit found zero remaining findings on symmetric-collections changes; the baseline therefore contains only remaining legacy locations. The gate prints the legacy-baseline count separately from newly detected findings and fails when the latter is nonzero.

To reduce debt, fix the finding first, then regenerate the baseline with the same strict, excluded-tree configuration and review the resulting diff. Do not regenerate it to accept new violations:

```bash
swiftlint lint --strict --config .swiftlint.yml --force-exclude --no-cache --quiet \
  --reporter json --write-baseline .swiftlint-baseline.json .
```

Coverage has no threshold in this gate and is not a readiness blocker.
