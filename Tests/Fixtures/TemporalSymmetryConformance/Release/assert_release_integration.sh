#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TOOL_ROOT="${CORE_CONFORMANCE_TOOL_ROOT:-$ROOT/.build/core-conformance-tools}"
TMP="$ROOT/.build/temporal-symmetry-release-integration-$(uuidgen | tr '[:upper:]' '[:lower:]')"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

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
jq -e '.finalExitClass == "success" and ([.entries[] | select(.decision == "admitted")] | length > 0)' \
    "$success_output/support-admission.json" >/dev/null
success_run="$(jq -r '.gateRunID' "$success_output/support-admission.json")"
core_run="$(jq -r '.coreAdmission.gateRunID' "$success_output/support-admission.json")"
core_report="$success_output/runs/$success_run/core/support-admission.json"
core_invocation="$success_output/runs/$success_run/invocation.json"
test -f "$core_report"
jq -e --arg core_run "$core_run" '
    .gateRunID == $core_run and .finalExitClass == "success"
' "$core_report" >/dev/null
jq -e --arg gate_run "$success_run" --arg core_run "$core_run" --arg core_path "runs/$success_run/core/support-admission.json" \
    --arg core_sha "$(shasum -a 256 "$core_report" | awk '{print $1}')" '
    .gateRunID == $gate_run
    and .coreGateRunID == $core_run
    and .coreAdmissionPath == $core_path
    and .coreReportSHA256 == $core_sha
' "$core_invocation" >/dev/null
jq -e --arg core_path "runs/$success_run/core/support-admission.json" \
    --arg core_sha "$(shasum -a 256 "$core_report" | awk '{print $1}')" '
    .coreAdmission.report.path == $core_path
    and .coreAdmission.report.sha256 == $core_sha
' "$success_output/support-admission.json" >/dev/null

unavailable_output="$TMP/unavailable"
expect_exit 2 env CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT" TEMPORAL_SYMMETRY_TOOL_ROOT="$TMP/missing-tools" \
    make -C "$ROOT" temporal-symmetry-release-check TEMPORAL_SYMMETRY_OUTPUT="$unavailable_output"
jq -e '.finalExitClass == "unavailable" and ([.entries[] | select(.decision == "admitted")] | length == 0)' \
    "$unavailable_output/support-admission.json" >/dev/null

echo "temporal-symmetry release integration checks passed"
