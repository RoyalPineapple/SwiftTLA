#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

require() {
    grep -Fq -- "$1" "$WORKFLOW" || {
        echo "missing release code-check contract: $1" >&2
        exit 1
    }
}

forbid() {
    if grep -Fq -- "$1" "$WORKFLOW"; then
        echo "forbidden release code-check contract: $1" >&2
        exit 1
    fi
}

require "release-code-check:"
require "run_hosted_diagnostics:"
require "submodules: recursive"
require "Validate pinned core-conformance baseline"
require 'baseline_path="Verification/CoreConformance/baselines"'
require 'git -C "$baseline_path" rev-parse --verify HEAD'
require 'git ls-tree HEAD "$baseline_path"'
require "Pinned core-conformance baseline is unavailable"
require "Pinned core-conformance baseline does not match the repository checkout"
require "Run SwiftLint (advisory)"
require "./scripts/lint-zero-new.sh"
require 'lint_status=$?'
require 'if [ "$lint_status" -ne 0 ]; then'
require "::warning::SwiftLint violations found"
require "Run full macOS test suite"
require "xcodebuild test -scheme SwiftTLA-Package -destination 'platform=macOS'"
require "Run coverage (hosted diagnostic)"
require "-enableCodeCoverage YES"
require 'coverage_status=$?'
require "Hosted macOS coverage runner failed"
require "github.event_name == 'workflow_dispatch' && inputs.run_hosted_diagnostics"
forbid "continue-on-error"
forbid "Run tests (hosted diagnostic)"
forbid 'test_status=$?'
forbid "Hosted macOS test runner failed"
forbid "swift test || true"
forbid "swift test --enable-code-coverage || true"

echo "release code-check workflow contract passed"
