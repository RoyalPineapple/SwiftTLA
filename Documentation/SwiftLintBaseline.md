# SwiftLint zero-new-violations gate

The approved local validation wrapper runs this gate. The gate runs SwiftLint in strict mode over authored Swift sources. It excludes only nested build products, package-manager/checkouts, and generated trees through [`.swiftlint.yml`](../.swiftlint.yml); product and test sources remain in scope.

`.swiftlint-baseline.json` records the current accepted findings. Each baseline entry contains its rule, file, line, character, and source text. The file uses a checkout-root placeholder, which the gate materializes to the current physical checkout path before passing it to SwiftLint.

The gate prints the baseline count separately from newly detected findings and fails when the latter is nonzero.

To reduce debt, fix the finding and update the baseline in the same reviewed change. Do not update it to accept new violations.

Coverage has no threshold in this gate and is not a readiness blocker.
