#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_GATE_SCRIPT="${CORE_SUPPORT_GATE_SCRIPT:-$SCRIPT_DIR/run_core_support_gate.sh}"
CASES_FILE="${TEMPORAL_SYMMETRY_CASES:-$PROJECT_ROOT/Verification/TemporalSymmetryConformance/cases.json}"
DIVERGENCES_FILE="${TEMPORAL_SYMMETRY_DIVERGENCES:-$PROJECT_ROOT/Verification/TemporalSymmetryConformance/divergences.json}"
SUPPORT_SURFACE_FILE="${TEMPORAL_SYMMETRY_SUPPORT_SURFACE:-$PROJECT_ROOT/Verification/TemporalSymmetryConformance/support-surface.json}"
TOOLCHAIN_FILE="${TEMPORAL_SYMMETRY_TOOLCHAIN:-$PROJECT_ROOT/Verification/CoreConformance/toolchain.json}"
TOOL_ROOT="${CORE_CONFORMANCE_TOOL_ROOT:-$PROJECT_ROOT/.build/core-conformance-tools}"
TEMPORAL_TOOL_ROOT="${TEMPORAL_SYMMETRY_TOOL_ROOT:-$TOOL_ROOT}"

usage() {
    echo "Usage: $0 --output <directory>" >&2
    exit 2
}

reject_unsafe_output() {
    python3 - "$@" <<'PY'
from pathlib import Path
import sys

output_root = Path(sys.argv[1]).resolve(strict=False)
report = Path(sys.argv[2]).resolve(strict=False)
protected = [Path(value).resolve(strict=False) for value in sys.argv[3:]]

def overlaps(first, second):
    return first == second or first.is_relative_to(second) or second.is_relative_to(first)

if any(overlaps(output_root, path) or overlaps(report, path) for path in protected):
    raise SystemExit("temporal-symmetry: output path collides with protected evidence")
PY
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
CORE_REPORT_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
if ! reject_unsafe_output "$OUTPUT" "$OUTPUT/runs/$GATE_RUN_ID/support-admission.json" \
    "$CASES_FILE" "$DIVERGENCES_FILE" "$SUPPORT_SURFACE_FILE" "$TOOLCHAIN_FILE"; then
    exit 2
fi

REPORT_ROOT="$OUTPUT"
preflight="available"
if [ -e "$OUTPUT" ] && [ ! -d "$OUTPUT" ]; then
    REPORT_ROOT="${OUTPUT}.failed-${GATE_RUN_ID}"
    preflight="unavailable"
    echo "temporal-symmetry: output path is not a directory: $OUTPUT" >&2
fi

RUN_ROOT="$REPORT_ROOT/runs/$GATE_RUN_ID"
REPORT="$RUN_ROOT/support-admission.json"
CORE_ROOT="$RUN_ROOT/core"
CORE_REPORT="$CORE_ROOT/support-admission.json"

if ! reject_unsafe_output "$REPORT_ROOT" "$REPORT" \
    "$CASES_FILE" "$DIVERGENCES_FILE" "$SUPPORT_SURFACE_FILE" "$TOOLCHAIN_FILE"; then
    exit 2
fi

mkdir -p "$REPORT_ROOT/runs"
mkdir "$RUN_ROOT"

export TEMPORAL_SYMMETRY_CASES="$CASES_FILE"
export TEMPORAL_SYMMETRY_DIVERGENCES="$DIVERGENCES_FILE"
export TEMPORAL_SYMMETRY_SUPPORT_SURFACE="$SUPPORT_SURFACE_FILE"
export TEMPORAL_SYMMETRY_TOOLCHAIN="$TOOLCHAIN_FILE"
export CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT"

prerequisite="available"
if [ "$preflight" != "available" ] || [ ! -f "$CASES_FILE" ] || [ ! -f "$DIVERGENCES_FILE" ] \
    || [ ! -f "$SUPPORT_SURFACE_FILE" ] || [ ! -f "$TOOLCHAIN_FILE" ]; then
    prerequisite="unavailable"
fi

set +e
"$CORE_GATE_SCRIPT" --output "$CORE_ROOT"
core_status=$?
set -e

if [ ! -f "$CORE_REPORT" ]; then
    prerequisite="unavailable"
    echo "temporal-symmetry: current core admission report is missing: $CORE_REPORT" >&2
fi

printf '{"gateRunID":"%s","coreReportID":"%s","prerequisite":"%s","coreGateExit":%s}\n' \
    "$GATE_RUN_ID" "$CORE_REPORT_ID" "$prerequisite" "$core_status" > "$RUN_ROOT/invocation.json"

set +e
(
    cd "$PROJECT_ROOT"
    CORE_CONFORMANCE_TOOL_ROOT="$TEMPORAL_TOOL_ROOT" swift run tlc-validate temporal-symmetry run \
        --evidence "$RUN_ROOT/cases" \
        --report "$REPORT" \
        --run-id "$GATE_RUN_ID" \
        --core-admission "$CORE_REPORT" \
        --core-report-id "$CORE_REPORT_ID" \
        --prerequisite "$prerequisite"
)
gate_status=$?
set -e

if [ -f "$REPORT" ]; then
    cp "$REPORT" "$REPORT_ROOT/support-admission.json"
else
    echo "temporal-symmetry: report generation failed: $REPORT" >&2
    exit 2
fi

echo "temporal-symmetry: retained run $GATE_RUN_ID at $RUN_ROOT" >&2
exit "$gate_status"
