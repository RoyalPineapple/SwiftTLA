#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/temporal-symmetry-conformance.yml"

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
require "make temporal-symmetry-release-check"
require "scripts/run_temporal_symmetry_support_gate.sh"
require ".build/temporal-symmetry-support-gate"
require "if: always()"
require "actions/upload-artifact@v4"
require 'case "$status" in'
require "0)"
require "1)"
require "2)"
require "TEMPORAL_SYMMETRY_EXIT"
require "exit 1"
require "exit 2"
forbid "enforcement_exit=0"
forbid "validate_upstream_parity.sh"
forbid "swift test --filter UpstreamParity"
forbid "curl "
forbid "wget "
forbid "-dumpTrace"
forbid "-loadTrace"
forbid ".dot"

echo "temporal-symmetry workflow checks passed"
