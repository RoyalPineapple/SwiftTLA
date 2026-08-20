#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CASES_FILE="${CORE_CONFORMANCE_CASES:-$PROJECT_ROOT/Verification/CoreConformance/cases.json}"
TOOL_ROOT="${CORE_CONFORMANCE_TOOL_ROOT:-$PROJECT_ROOT/.build/core-conformance-tools}"

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

[ -f "$CASES_FILE" ] || { echo "core-conformance: cases manifest is missing: $CASES_FILE" >&2; exit 2; }
python3 - "$CASES_FILE" "$CASE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
if manifest.get("schema") != "CoreConformanceCases":
    raise SystemExit("core-conformance: unsupported cases manifest schema")
ids = [entry.get("id") for entry in manifest.get("cases", [])]
if sys.argv[2] != "all" and sys.argv[2] not in ids:
    raise SystemExit("core-conformance: unknown core-conformance case: " + sys.argv[2])
if sys.argv[2] == "all" and not ids:
    raise SystemExit("core-conformance: cases manifest has no cases")
PY

[ ! -e "$OUTPUT" ] || { echo "core-conformance: output directory already exists: $OUTPUT" >&2; exit 2; }
"$SCRIPT_DIR/setup-core-conformance-tools.sh" --tool-root "$TOOL_ROOT" --cases "$CASES_FILE" >/dev/null

export CORE_CONFORMANCE_CASES="$CASES_FILE"
export CORE_CONFORMANCE_TOOL_ROOT="$TOOL_ROOT"
export CORE_CONFORMANCE_INPUT_ROOT="$TOOL_ROOT/inputs"
cd "$PROJECT_ROOT"
swift run tlc-validate core-conformance run --case "$CASE" --output "$OUTPUT"
