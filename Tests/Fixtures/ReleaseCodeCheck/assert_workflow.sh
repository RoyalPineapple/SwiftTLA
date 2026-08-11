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
require "Run SwiftLint (advisory)"
require "./scripts/lint-zero-new.sh"
require 'lint_status=$?'
require 'if [ "$lint_status" -ne 0 ]; then'
require "::warning::SwiftLint violations found"
require "Run tests"
require "xcodebuild test -scheme SwiftTLA-Package -destination 'platform=macOS'"
require "Run coverage"
require "-enableCodeCoverage YES"
forbid "continue-on-error"
forbid "swift test || true"
forbid "swift test --enable-code-coverage || true"

echo "release code-check workflow contract passed"
