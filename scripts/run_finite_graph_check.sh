#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CASES_FILE="${FINITE_GRAPH_CASES:-$PROJECT_ROOT/Verification/FiniteGraph/cases.json}"
TOOL_ROOT="${FINITE_GRAPH_TOOL_ROOT:-$PROJECT_ROOT/.build/finite-graph-tools}"

usage() {
    echo "Usage: $0 --case <case-or-all> --output <directory>" >&2
    exit 2
}

CASE=""
OUTPUT=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --case) [ -z "$CASE" ] || usage; CASE="${2:-}"; shift 2 ;;
        --output) [ -z "$OUTPUT" ] || usage; OUTPUT="${2:-}"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$CASE" ] && [ -n "$OUTPUT" ] || usage

"$SCRIPT_DIR/setup-finite-graph-tools.sh" --tool-root "$TOOL_ROOT" --cases "$CASES_FILE" >/dev/null

export FINITE_GRAPH_CASES="$CASES_FILE"
export FINITE_GRAPH_TOOL_ROOT="$TOOL_ROOT"
export FINITE_GRAPH_INPUT_ROOT="$TOOL_ROOT/inputs"
cd "$PROJECT_ROOT"
swift run tlc-validate finite-graph run --case "$CASE" --output "$OUTPUT"
