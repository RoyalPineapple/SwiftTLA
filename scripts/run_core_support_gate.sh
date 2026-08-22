#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CASES_FILE="${CORE_CONFORMANCE_CASES:-$PROJECT_ROOT/Verification/CoreConformance/cases.json}"
TOOL_ROOT="${CORE_CONFORMANCE_TOOL_ROOT:-$PROJECT_ROOT/.build/core-conformance-tools}"
DIVERGENCES_FILE="${CORE_CONFORMANCE_DIVERGENCES:-$PROJECT_ROOT/Verification/CoreConformance/divergences.json}"
SUPPORT_SURFACE_FILE="${CORE_CONFORMANCE_SUPPORT_SURFACE:-$PROJECT_ROOT/Verification/CoreConformance/support-surface.json}"
SETUP_SCRIPT="${CORE_CONFORMANCE_SETUP_SCRIPT:-$SCRIPT_DIR/setup-core-conformance-tools.sh}"

usage() {
    echo "Usage: $0 --output <directory>" >&2
    exit 2
}

OUTPUT=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ -z "$OUTPUT" ] || usage; OUTPUT="${2:-}"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$OUTPUT" ] || usage

GATE_RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
REPORT_ROOT="$OUTPUT"
preflight="available"
if [ -e "$OUTPUT" ] && [ ! -d "$OUTPUT" ]; then
    REPORT_ROOT="${OUTPUT}.failed-${GATE_RUN_ID}"
    preflight="unavailable"
    echo "core-support-gate: output path is not a directory: $OUTPUT" >&2
fi

mkdir -p "$REPORT_ROOT/runs"
RUN_ROOT="$REPORT_ROOT/runs/$GATE_RUN_ID"
mkdir "$RUN_ROOT"
REPORT="$RUN_ROOT/support-admission.json"

export CORE_CONFORMANCE_CASES="$CASES_FILE"
export CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT"
export CORE_CONFORMANCE_INPUT_ROOT="$TOOL_ROOT/inputs"
export CORE_CONFORMANCE_DIVERGENCES="$DIVERGENCES_FILE"
export CORE_CONFORMANCE_SUPPORT_SURFACE="$SUPPORT_SURFACE_FILE"

prerequisite="available"
run_status=0
if [ "$preflight" != "available" ] || [ ! -f "$CASES_FILE" ]; then
    prerequisite="unavailable"
    run_status=2
    [ -f "$CASES_FILE" ] || echo "core-support-gate: cases manifest is missing: $CASES_FILE" >&2
elif ! "$SETUP_SCRIPT" --tool-root "$TOOL_ROOT" --cases "$CASES_FILE"; then
    prerequisite="unavailable"
    run_status=2
else
    set +e
    (
        cd "$PROJECT_ROOT"
        swift run tlc-validate core-conformance run --case all --output "$RUN_ROOT/cases" --run-id "$GATE_RUN_ID"
    )
    run_status=$?
    set -e
fi

printf '{"gateRunID":"%s","prerequisite":"%s","conformanceExitCode":%s}\n' \
    "$GATE_RUN_ID" "$prerequisite" "$run_status" > "$RUN_ROOT/invocation.json"

set +e
(
    cd "$PROJECT_ROOT"
    swift run tlc-validate core-conformance gate \
        --evidence "$RUN_ROOT/cases" \
        --report "$REPORT" \
        --run-id "$GATE_RUN_ID" \
        --prerequisite "$prerequisite" \
        --conformance-exit "$run_status"
)
gate_status=$?
set -e

if [ -f "$REPORT" ]; then
    "$SCRIPT_DIR/current_evidence_report.py" write "$REPORT_ROOT" "$REPORT"
else
    echo "core-support-gate: report generation failed: $REPORT" >&2
    exit 2
fi

echo "core-support-gate: retained run $GATE_RUN_ID at $RUN_ROOT" >&2
exit "$gate_status"
