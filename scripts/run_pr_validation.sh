#!/usr/bin/env bash
set -euo pipefail

echo "Validate local CI command contracts"
bash Tests/Fixtures/LocalCI/assert_commands.sh

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

echo "Run PR smoke tests"
./scripts/run_pr_smoke_tests.sh

echo "Build package"
swift build

echo "Build macro plugin"
swift build --target SwiftTLAMacros

echo "Build downstream examples"
make examples
