#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CASES_FILE="${TEMPORAL_SYMMETRY_CASES:-$PROJECT_ROOT/Verification/TemporalSymmetryConformance/cases.json}"
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

if [ -e "$OUTPUT" ]; then
    echo "temporal-symmetry: output already exists: $OUTPUT" >&2
    exit 2
fi

export TEMPORAL_SYMMETRY_CASES="$CASES_FILE"
export CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT"

"$SCRIPT_DIR/setup-core-conformance-tools.sh" --tool-root "$TOOL_ROOT" >/dev/null

(
    cd "$PROJECT_ROOT"
    swift run tlc-validate temporal-symmetry run --output "$OUTPUT"
)
