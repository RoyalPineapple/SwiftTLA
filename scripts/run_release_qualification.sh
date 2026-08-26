#!/usr/bin/env bash
set -euo pipefail

tool_root="${FINITE_GRAPH_TOOL_ROOT:-$PWD/.build/finite-graph-tools}"

echo "Validate release code-check contract"
bash Tests/Fixtures/ReleaseCodeCheck/assert_workflow.sh

echo "Run SwiftLint (advisory)"
set +e
./scripts/lint-zero-new.sh
lint_status=$?
set -e
if [ "$lint_status" -ne 0 ]; then
  echo "warning: SwiftLint violations found; continuing because lint is advisory" >&2
fi

echo "Run tests serially"
# Model-checking tests can traverse large, bounded formal action trees. Keep
# the release qualification serial so independent test targets do not compete
# for the cooperative worker stack.
swift test --no-parallel

echo "Run coverage serially"
swift test --enable-code-coverage --no-parallel

echo "Build package"
swift build

echo "Build macro plugin"
swift build --target SwiftTLAMacros

echo "Build downstream examples"
make examples

echo "Run temporal-symmetry conformance"
FINITE_GRAPH_TOOL_ROOT="$tool_root" make temporal-symmetry-conformance
