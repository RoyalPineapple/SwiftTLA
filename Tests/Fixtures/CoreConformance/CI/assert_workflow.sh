#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/core-conformance.yml"

require() {
    grep -Fq -- "$1" "$WORKFLOW" || {
        echo "missing workflow contract: $1" >&2
        exit 1
    }
}

forbid() {
    if grep -Fq -- "$1" "$WORKFLOW"; then
        echo "forbidden workflow command: $1" >&2
        exit 1
    fi
}

require "runs-on: macos-15"
require './scripts/setup-core-conformance-tools.sh --tool-root "$CORE_CONFORMANCE_TOOL_ROOT" --cases Verification/CoreConformance/cases.json'
require "make core-conformance"
require "if: always()"
require "actions/upload-artifact@v4"
require 'case "$status" in'
require "0)"
require "1)"
require "2)"
require "CORE_CONFORMANCE_EXIT"
require "exit 1"
require "exit 2"
forbid "baseline"
forbid "validate_upstream_parity.sh"
forbid "swift test --filter UpstreamParity"
forbid "curl "
forbid "wget "
forbid "-dumpTrace"
forbid "-loadTrace"
forbid ".dot"

echo "core-conformance workflow checks passed"
