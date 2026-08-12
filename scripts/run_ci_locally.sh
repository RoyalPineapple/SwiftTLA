#!/usr/bin/env bash
set -euo pipefail

tool_root="${CORE_CONFORMANCE_TOOL_ROOT:-$PWD/.build/core-conformance-tools}"

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

echo "Run tests"
swift test

echo "Run coverage"
swift test --enable-code-coverage

echo "Build package"
swift build

echo "Build macro plugin"
swift build --target SwiftTLAMacros

echo "Validate core-conformance workflow contract"
Tests/Fixtures/CoreConformance/CI/assert_workflow.sh

echo "Run mandatory core-support gate"
CORE_CONFORMANCE_TOOL_ROOT="$tool_root" make core-support-gate
