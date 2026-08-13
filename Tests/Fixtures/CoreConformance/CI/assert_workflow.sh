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
require "schedule:"
require "cron: '0 2 * * *'"
require "check-head:"
require "listWorkflowRuns"
require "workflow_id: 'core-conformance.yml'"
require "run_expensive"
require "submodules: recursive"
require "Validate pinned core-conformance baseline"
require 'baseline_path="Verification/CoreConformance/baselines"'
require 'git -C "$baseline_path" rev-parse --verify HEAD'
require 'git ls-tree HEAD "$baseline_path"'
require 'Pinned core-conformance baseline is unavailable'
require 'Pinned core-conformance baseline does not match the repository checkout'
require "make core-support-gate"
require ".build/core-support-gate"
require "if: always()"
require "actions/upload-artifact@v4"
require 'case "$status" in'
require "0)"
require "1)"
require "2)"
require "CORE_CONFORMANCE_EXIT"
require "enforcement_exit=0"
require "exact external verifier or evidence was unavailable"
require "exit 1"
require "exit 2"
forbid "validate_upstream_parity.sh"
forbid "swift test --filter UpstreamParity"
forbid "make core-conformance"
forbid "pull_request:"
forbid "curl "
forbid "wget "
forbid "-dumpTrace"
forbid "-loadTrace"
forbid ".dot"

echo "core-conformance workflow checks passed"
