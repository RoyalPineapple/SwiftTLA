#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
GATE="$ROOT/scripts/run_temporal_symmetry_support_gate.sh"
TMP="$ROOT/.build/temporal-symmetry-command-$(uuidgen | tr '[:upper:]' '[:lower:]')"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

expect_exit() {
    local expected="$1"
    shift
    set +e
    "$@" >"$TMP/stdout" 2>"$TMP/stderr"
    local status=$?
    set -e
    if [ "$status" -ne "$expected" ]; then
        echo "expected exit $expected, got $status: $*" >&2
        cat "$TMP/stderr" >&2
        exit 1
    fi
}

core_run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
core_report="$TMP/core-admission.json"
expect_exit 2 env CORE_CONFORMANCE_CASES="$ROOT/Verification/CoreConformance/cases.json" \
    swift run tlc-validate core-conformance gate \
    --evidence "$TMP/missing-core-evidence" \
    --report "$core_report" \
    --run-id "$core_run_id" \
    --prerequisite unavailable
test -f "$core_report"

run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
report="$TMP/temporal-symmetry-admission.json"
expect_exit 2 swift run tlc-validate temporal-symmetry gate \
    --evidence "$TMP/missing-comparisons" \
    --report "$report" \
    --run-id "$run_id" \
    --core-admission "$core_report" \
    --core-report-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --prerequisite unavailable
test -f "$report"
jq -e '.schema == "TemporalSymmetryAdmission" and .gateRunID == $run and .finalExitClass == "unavailable"' \
    --arg run "$run_id" "$report" >/dev/null
case_run="$TMP/missing-comparisons/temporal-always-none/case-run.json"
test -f "$case_run"
jq -e '.schema == "TemporalSymmetryCaseRun" and .gateRunID == $run and .status == "prepared" and .diagnosticCode == "awaiting-pinned-tlc-comparison" and .swiftGraphStateCount == 3' \
    --arg run "$run_id" "$case_run" >/dev/null

run_report="$TMP/temporal-symmetry-run-admission.json"
expect_exit 2 swift run tlc-validate temporal-symmetry run \
    --evidence "$TMP/missing-comparisons" \
    --report "$run_report" \
    --run-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --core-admission "$core_report" \
    --core-report-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --prerequisite unavailable
test -f "$run_report"

assert_invalid_register() {
    local name="$1"
    local environment_name="$2"
    local register="$3"
    local invalid_report="$TMP/$name-admission.json"
    expect_exit 2 env "$environment_name=$register" swift run tlc-validate temporal-symmetry gate \
        --evidence "$TMP/missing-comparisons" \
        --report "$invalid_report" \
        --run-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
        --core-admission "$core_report" \
        --core-report-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
        --prerequisite available
    test -f "$invalid_report"
    jq -e '.finalExitClass == "unavailable" and any(.entries[]; .reasonCodes | index("invalidRegister"))' \
        "$invalid_report" >/dev/null
}

malformed_cases="$TMP/malformed-cases.json"
printf '%s\n' '{"schema":"invalid","cases":[]}' > "$malformed_cases"
assert_invalid_register malformed TEMPORAL_SYMMETRY_CASES "$malformed_cases"

empty_cases="$TMP/empty-cases.json"
jq '.cases = []' "$ROOT/Verification/TemporalSymmetryConformance/cases.json" > "$empty_cases"
assert_invalid_register empty TEMPORAL_SYMMETRY_CASES "$empty_cases"

cross_invalid_surface="$TMP/cross-invalid-surface.json"
jq '.entries[0].mandatoryCaseIDs = ["missing-case"]' \
    "$ROOT/Verification/TemporalSymmetryConformance/support-surface.json" > "$cross_invalid_surface"
assert_invalid_register cross-invalid TEMPORAL_SYMMETRY_SUPPORT_SURFACE "$cross_invalid_surface"

manifest="$ROOT/Verification/TemporalSymmetryConformance/cases.json"
manifest_digest_before="$(shasum -a 256 "$manifest" | awk '{print $1}')"
expect_exit 2 swift run tlc-validate temporal-symmetry gate \
    --evidence "$TMP/missing-comparisons" \
    --report "$manifest" \
    --run-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --core-admission "$core_report" \
    --core-report-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --prerequisite unavailable
manifest_digest_after="$(shasum -a 256 "$manifest" | awk '{print $1}')"
test "$manifest_digest_before" = "$manifest_digest_after"

manifest_alias="$TMP/cases-alias.json"
ln -s "$manifest" "$manifest_alias"
expect_exit 2 swift run tlc-validate temporal-symmetry gate \
    --evidence "$TMP/missing-comparisons" \
    --report "$manifest_alias" \
    --run-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --core-admission "$core_report" \
    --core-report-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --prerequisite unavailable
manifest_digest_after_alias="$(shasum -a 256 "$manifest" | awk '{print $1}')"
test "$manifest_digest_before" = "$manifest_digest_after_alias"

expect_exit 2 "$GATE" --output "$manifest"
manifest_digest_after_wrapper="$(shasum -a 256 "$manifest" | awk '{print $1}')"
test "$manifest_digest_before" = "$manifest_digest_after_wrapper"

wrapper_alias="$TMP/cases-output-alias.json"
ln -s "$manifest" "$wrapper_alias"
expect_exit 2 "$GATE" --output "$wrapper_alias"
manifest_digest_after_wrapper_alias="$(shasum -a 256 "$manifest" | awk '{print $1}')"
test "$manifest_digest_before" = "$manifest_digest_after_wrapper_alias"

wrapper_output="$TMP/wrapper-output"
expect_exit 2 env CORE_CONFORMANCE_CASES="$TMP/missing-cases.json" \
    "$GATE" --output "$wrapper_output"
latest_report="$wrapper_output/support-admission.json"
test -f "$latest_report"
wrapper_run="$(jq -r '.gateRunID' "$latest_report")"
test -f "$wrapper_output/runs/$wrapper_run/support-admission.json"
test -f "$wrapper_output/runs/$wrapper_run/invocation.json"

echo "temporal-symmetry command checks passed"
