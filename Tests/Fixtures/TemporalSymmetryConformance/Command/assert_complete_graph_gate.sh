#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TOOL_ROOT="${CORE_CONFORMANCE_TOOL_ROOT:-$ROOT/.build/core-conformance-tools}"
TMP="$ROOT/.build/temporal-symmetry-complete-graph-$(uuidgen | tr '[:upper:]' '[:lower:]')"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

set +e
CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT" "$ROOT/scripts/run_temporal_symmetry_support_gate.sh" --output "$TMP/source"
source_status=$?
set -e
test "$source_status" -eq 0

run_id="$(jq -r '.gateRunID' "$TMP/source/support-admission.json")"
core_report="$TMP/source/runs/$run_id/core/support-admission.json"
source_cases="$TMP/source/runs/$run_id/cases"
test -f "$core_report"
test -d "$source_cases"

expect_unavailable() {
    local name="$1"
    local cases="$2"
    local diagnostic="$3"
    local report="$TMP/$name/report.json"
    mkdir -p "$(dirname "$report")"
    set +e
    (
        cd "$ROOT"
        swift run tlc-validate temporal-symmetry gate \
            --evidence "$cases" --report "$report" --run-id "$run_id" \
            --core-admission "$core_report" --core-report-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
            --prerequisite available
    ) >"$TMP/$name/stdout" 2>"$TMP/$name/stderr"
    local status=$?
    set -e
    test "$status" -eq 2
    jq -e '.finalExitClass == "unavailable" and ([.entries[] | select(.decision == "admitted")] | length == 0)' \
        "$report" >/dev/null
    grep -Fq -- "$diagnostic" "$TMP/$name/stderr"
}

prepare_attack() {
    local name="$1"
    local destination="$TMP/$name/cases"
    mkdir -p "$(dirname "$destination")"
    cp -a "$source_cases" "$destination"
    printf '%s' "$destination"
}

refresh_graph_digest() {
    local comparison="$1"
    local graph="$2"
    local digest
    digest="$(shasum -a 256 "$graph" | awk '{print $1}')"
    jq --arg digest "$digest" '.completeGraphEvidence.graphEvents.sha256 = $digest' "$comparison" > "$comparison.tmp"
    mv "$comparison.tmp" "$comparison"
}

bind_copied_complete_graph_artifacts() {
    local comparison="$1"
    local cases="$2"
    local graph="$cases/temporal-always-none/complete-graph-pass/graph-events.jsonl"
    local result="$cases/temporal-always-none/complete-graph-pass/tlc-result.json"
    local relative_cases="${cases#$ROOT/}"
    local graph_digest result_digest
    graph_digest="$(shasum -a 256 "$graph" | awk '{print $1}')"
    result_digest="$(shasum -a 256 "$result" | awk '{print $1}')"
    jq \
        --arg graph_path "$relative_cases/temporal-always-none/complete-graph-pass/graph-events.jsonl" \
        --arg graph_digest "$graph_digest" \
        --arg result_path "$relative_cases/temporal-always-none/complete-graph-pass/tlc-result.json" \
        --arg result_digest "$result_digest" \
        '.completeGraphEvidence.graphEvents.path = $graph_path
         | .completeGraphEvidence.graphEvents.sha256 = $graph_digest
         | .completeGraphEvidence.result.path = $result_path
         | .completeGraphEvidence.result.sha256 = $result_digest' \
        "$comparison" > "$comparison.tmp"
    mv "$comparison.tmp" "$comparison"
}

refresh_result_digest() {
    local comparison="$1"
    local result="$2"
    local digest
    digest="$(shasum -a 256 "$result" | awk '{print $1}')"
    jq --arg digest "$digest" '.completeGraphEvidence.result.sha256 = $digest' "$comparison" > "$comparison.tmp"
    mv "$comparison.tmp" "$comparison"
}

wrong_run_cases="$(prepare_attack wrong-run)"
wrong_run_comparison="$wrong_run_cases/temporal-always-none/temporal-comparison.json"
bind_copied_complete_graph_artifacts "$wrong_run_comparison" "$wrong_run_cases"
wrong_run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
jq --arg run "$wrong_run_id" '.completeGraphEvidence.graphRunID = $run' "$wrong_run_comparison" > "$wrong_run_comparison.tmp"
mv "$wrong_run_comparison.tmp" "$wrong_run_comparison"
expect_unavailable wrong-run "$wrong_run_cases" "foreign complete graph run"

foreign_cases="$(prepare_attack foreign-graph)"
foreign_comparison="$foreign_cases/temporal-always-none/temporal-comparison.json"
foreign_graph="$foreign_cases/temporal-always-none/complete-graph-pass/graph-events.jsonl"
bind_copied_complete_graph_artifacts "$foreign_comparison" "$foreign_cases"
cp "$foreign_cases/temporal-eventually-none/graph-events.jsonl" "$foreign_graph"
refresh_graph_digest "$foreign_comparison" "$foreign_graph"
expect_unavailable foreign-graph "$foreign_cases" "case ID"

incomplete_cases="$(prepare_attack nonexhaustive-result)"
incomplete_comparison="$incomplete_cases/temporal-always-none/temporal-comparison.json"
incomplete_result="$incomplete_cases/temporal-always-none/complete-graph-pass/tlc-result.json"
bind_copied_complete_graph_artifacts "$incomplete_comparison" "$incomplete_cases"
jq '.status = 12 | .reportedExhaustiveCompletion = false | .isViolation = true' "$incomplete_result" > "$incomplete_result.tmp"
mv "$incomplete_result.tmp" "$incomplete_result"
refresh_result_digest "$incomplete_comparison" "$incomplete_result"
expect_unavailable nonexhaustive-result "$incomplete_cases" "incomplete complete graph result"

echo "complete graph gate attack checks passed"
