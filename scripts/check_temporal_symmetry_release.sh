#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=""

usage() {
    echo "Usage: $0 --output <directory>" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ -z "$OUTPUT" ] || usage; OUTPUT="${2:-}"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$OUTPUT" ] || usage

echo "Validate temporal-symmetry source-of-truth registers"
(
    cd "$PROJECT_ROOT"
    swift test --filter TemporalSymmetryRegisterTests
)

set +e
"$PROJECT_ROOT/scripts/run_temporal_symmetry_support_gate.sh" --output "$OUTPUT"
status=$?
set -e

report="$OUTPUT/support-admission.json"
if [ ! -f "$report" ]; then
    echo "temporal-symmetry release-check: retained admission report is missing" >&2
    exit 2
fi

validate_report() {
    if ! jq -e "$1" "$report" >/dev/null; then
        echo "temporal-symmetry release-check: retained report does not match exit $status" >&2
        exit 2
    fi
}

case "$status" in
    0)
        validate_report '
          .schema == "TemporalSymmetryAdmission"
          and .finalExitClass == "success"
          and .unexplainedDivergenceCount == 0
          and ([.entries[] | select(.decision == "blocked")] | length == 0)
          and ([.entries[] | select(.decision == "admitted" and (.reasonCodes | length != 0))] | length == 0)
        '
        if ! jq -e --slurpfile surface "$PROJECT_ROOT/Verification/TemporalSymmetryConformance/support-surface.json" '
          . as $report
          | [$surface[0].entries[] | select(.requestedStatus == "requested") | .id] as $requested
          | ($report.entries | map({key: .supportID, value: .}) | from_entries) as $reported
          | all($requested[]; ($reported[.] | .decision == "admitted" and (.reasonCodes | length == 0)))
        ' "$report" >/dev/null; then
            echo "temporal-symmetry release-check: success report does not admit every requested source-of-truth entry" >&2
            exit 2
        fi
        ;;
    1)
        validate_report '
          .schema == "TemporalSymmetryAdmission"
          and .finalExitClass == "blocked"
          and any(.entries[]; .decision == "blocked")
        '
        ;;
    2)
        validate_report '
          .schema == "TemporalSymmetryAdmission"
          and .finalExitClass == "unavailable"
          and ([.entries[] | select(.decision == "admitted")] | length == 0)
        '
        ;;
    *)
        echo "temporal-symmetry release-check: unrecognized gate exit $status" >&2
        exit 2
        ;;
esac

exit "$status"
