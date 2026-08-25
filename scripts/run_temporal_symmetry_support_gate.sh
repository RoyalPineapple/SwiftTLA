#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_RUNNER="${CORE_CONFORMANCE_RUNNER:-$SCRIPT_DIR/run_core_conformance.sh}"
CASES_FILE="${TEMPORAL_SYMMETRY_CASES:-$PROJECT_ROOT/Verification/TemporalSymmetryConformance/cases.json}"
DIVERGENCES_FILE="${TEMPORAL_SYMMETRY_DIVERGENCES:-$PROJECT_ROOT/Verification/TemporalSymmetryConformance/divergences.json}"
SUPPORT_SURFACE_FILE="${TEMPORAL_SYMMETRY_SUPPORT_SURFACE:-$PROJECT_ROOT/Verification/TemporalSymmetryConformance/support-surface.json}"
TOOLCHAIN_FILE="${TEMPORAL_SYMMETRY_TOOLCHAIN:-$PROJECT_ROOT/Verification/CoreConformance/toolchain.json}"
TOOL_ROOT="${CORE_CONFORMANCE_TOOL_ROOT:-$PROJECT_ROOT/.build/core-conformance-tools}"

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
if [ -e "$OUTPUT" ]; then
    echo "temporal-symmetry: output already exists: $OUTPUT" >&2
    exit 2
fi

RUN_ROOT="$OUTPUT/runs/$GATE_RUN_ID"
REPORT="$RUN_ROOT/support-admission.json"
mkdir -p "$RUN_ROOT"

export TEMPORAL_SYMMETRY_CASES="$CASES_FILE"
export TEMPORAL_SYMMETRY_DIVERGENCES="$DIVERGENCES_FILE"
export TEMPORAL_SYMMETRY_SUPPORT_SURFACE="$SUPPORT_SURFACE_FILE"
export TEMPORAL_SYMMETRY_TOOLCHAIN="$TOOLCHAIN_FILE"
export CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT"

prerequisite="available"
for required in "$CASES_FILE" "$DIVERGENCES_FILE" "$SUPPORT_SURFACE_FILE" "$TOOLCHAIN_FILE"; do
    if [ ! -f "$required" ]; then prerequisite="unavailable"; fi
done

set +e
"$CORE_RUNNER" --case all --output "$RUN_ROOT/core"
core_status=$?
set -e
if [ "$core_status" -ne 0 ]; then prerequisite="unavailable"; fi

printf '{"gateRunID":"%s","prerequisite":"%s","coreConformanceExit":%s}\n' \
    "$GATE_RUN_ID" "$prerequisite" "$core_status" > "$RUN_ROOT/invocation.json"

set +e
(
    cd "$PROJECT_ROOT"
    swift run tlc-validate temporal-symmetry run \
        --evidence "$RUN_ROOT/cases" \
        --report "$REPORT" \
        --run-id "$GATE_RUN_ID" \
        --prerequisite "$prerequisite"
)
gate_status=$?
set -e

if [ ! -f "$REPORT" ]; then
    echo "temporal-symmetry: report generation failed: $REPORT" >&2
    exit 2
fi
"$SCRIPT_DIR/current_evidence_report.py" write "$OUTPUT" "$REPORT"

echo "temporal-symmetry: retained run $GATE_RUN_ID at $RUN_ROOT" >&2
exit "$gate_status"
