#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TOOL_ROOT="${CORE_CONFORMANCE_TOOL_ROOT:-$ROOT/.build/core-conformance-tools}"
TMP="$ROOT/.build/temporal-symmetry-release-integration-$(uuidgen | tr '[:upper:]' '[:lower:]')"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

current_report() {
    "$ROOT/scripts/current_evidence_report.py" resolve "$1"
}

expect_exit() {
    local expected="$1"
    shift
    set +e
    "$@" >"$TMP/stdout" 2>"$TMP/stderr"
    local command_status=$?
    set -e
    test "$command_status" -eq "$expected"
}

success_output="$TMP/success"
expect_exit 0 env CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT" \
    make -C "$ROOT" temporal-symmetry-release-check TEMPORAL_SYMMETRY_OUTPUT="$success_output"
success_report="$(current_report "$success_output")"
jq -e '.finalExitClass == "success" and ([.entries[] | select(.decision == "admitted")] | length > 0)' \
    "$success_report" >/dev/null
success_run="$(jq -r '.gateRunID' "$success_report")"
core_invocation="$success_output/runs/$success_run/invocation.json"
test -f "$success_output/runs/$success_run/core/hour-clock/core-decision.json"
test -f "$success_output/runs/$success_run/core/die-hard-type-ok/core-decision.json"
test -f "$success_output/runs/$success_run/core/multicar-elevator/core-decision.json"
jq -e --arg gate_run "$success_run" '
    .gateRunID == $gate_run
    and .prerequisite == "available"
    and .coreConformanceExit == 0
' "$core_invocation" >/dev/null

unavailable_output="$TMP/unavailable"
expect_exit 2 env CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT" CORE_CONFORMANCE_RUNNER="$TMP/missing-core-runner" \
    make -C "$ROOT" temporal-symmetry-release-check TEMPORAL_SYMMETRY_OUTPUT="$unavailable_output"
unavailable_report="$(current_report "$unavailable_output")"
jq -e '.finalExitClass == "unavailable" and ([.entries[] | select(.decision == "admitted")] | length == 0)' \
    "$unavailable_report" >/dev/null

echo "temporal-symmetry release integration checks passed"
