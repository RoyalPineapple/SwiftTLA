#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUN="$ROOT/scripts/run_core_conformance.sh"
SETUP="$ROOT/scripts/setup-core-conformance-tools.sh"
GATE="$ROOT/scripts/run_core_support_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

current_report() {
    "$ROOT/scripts/current_evidence_report.py" resolve "$1"
}

expect_failure() {
    local expected="$1"
    shift
    if "$@" >"$TMP/stdout" 2>"$TMP/stderr"; then
        echo "expected command to fail: $*" >&2
        exit 1
    fi
    grep -F "$expected" "$TMP/stderr" >/dev/null
}

cat >"$TMP/cases.json" <<'JSON'
{"schema":"CoreConformanceCases","cases":[{"id":"hour-clock"}]}
JSON

expect_failure "unknown core-conformance case" \
    env CORE_CONFORMANCE_CASES="$TMP/cases.json" "$RUN" --case invalid --output "$TMP/output"

python3 - "$ROOT/Verification/CoreConformance/cases.json" "$TMP/incomplete-mapping.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
del manifest["cases"][0]["identityMapping"]["variables"]["hr"]
with open(sys.argv[2], "w", encoding="utf-8") as destination:
    json.dump(manifest, destination)
PY
expect_failure "incomplete or non-identity variable mapping" \
    env CORE_CONFORMANCE_CASES="$TMP/incomplete-mapping.json" swift run tlc-validate core-conformance run --case hour-clock --output "$TMP/mapping-output"

mkdir "$TMP/output"
expect_failure "output directory already exists" \
    env CORE_CONFORMANCE_CASES="$TMP/cases.json" "$RUN" --case hour-clock --output "$TMP/output"

python3 - "$ROOT/Verification/CoreConformance/toolchain.json" "$TMP/toolchain.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    lock = json.load(source)
lock["tlc"]["jar"]["sha256"] = "0" * 64
with open(sys.argv[2], "w") as destination:
    json.dump(lock, destination)
PY
expect_failure "does not match the accepted TLC reference pin" \
    "$SETUP" --toolchain "$TMP/toolchain.json"

mkdir -p "$TMP/project/Verification/CoreConformance/fixtures/local" "$TMP/tool-root"
printf '%s\n' '---- MODULE LocalFixture ----' '====' >"$TMP/project/Verification/CoreConformance/fixtures/local/LocalFixture.tla"
printf '%s\n' 'SPECIFICATION Spec' >"$TMP/project/Verification/CoreConformance/fixtures/local/LocalFixture.cfg"
printf '%s\n' '---- MODULE LocalImport ----' '====' >"$TMP/project/Verification/CoreConformance/fixtures/local/LocalImport.tla"
cat >"$TMP/local-fixtures.json" <<JSON
{
  "schema": "CoreConformanceCases",
  "cases": [{
    "id": "local-fixture",
    "module": "fixtures/local/LocalFixture.tla",
    "configuration": "fixtures/local/LocalFixture.cfg",
    "imports": ["fixtures/local/LocalImport.tla"]
  }]
}
JSON
CORE_CONFORMANCE_PROJECT_ROOT="$TMP/project" "$SETUP" --cases "$TMP/local-fixtures.json" --tool-root "$TMP/tool-root" --stage-inputs-only >/dev/null
cmp "$TMP/project/Verification/CoreConformance/fixtures/local/LocalFixture.tla" "$TMP/tool-root/inputs/fixtures/local/LocalFixture.tla"
cmp "$TMP/project/Verification/CoreConformance/fixtures/local/LocalFixture.cfg" "$TMP/tool-root/inputs/fixtures/local/LocalFixture.cfg"
cmp "$TMP/project/Verification/CoreConformance/fixtures/local/LocalImport.tla" "$TMP/tool-root/inputs/fixtures/local/LocalImport.tla"

python3 - "$TMP/local-fixtures.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
manifest["cases"][0]["module"] = "fixtures/../../outside.tla"
with open(sys.argv[1], "w", encoding="utf-8") as destination:
    json.dump(manifest, destination)
PY
expect_failure "fixture is outside retained fixtures" \
    env CORE_CONFORMANCE_PROJECT_ROOT="$TMP/project" "$SETUP" --cases "$TMP/local-fixtures.json" --tool-root "$TMP/tool-root" --stage-inputs-only

GATE_RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
GATE_REPORT="$TMP/support-admission.json"
if env CORE_CONFORMANCE_CASES="$ROOT/Verification/CoreConformance/cases.json" \
    swift run tlc-validate core-conformance gate \
    --evidence "$TMP/missing-evidence" \
    --report "$GATE_REPORT" \
    --run-id "$GATE_RUN_ID" \
    --prerequisite unavailable >"$TMP/gate-stdout" 2>"$TMP/gate-stderr"; then
    echo "expected unavailable prerequisite gate to fail" >&2
    exit 1
fi
test -f "$GATE_REPORT"
python3 - "$GATE_REPORT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    report = json.load(source)
if report.get("finalExitClass") != "blocked":
    raise SystemExit("missing blocked admission report")
if not any("missingPrerequisite" in entry.get("reasonCodes", []) for entry in report.get("entries", [])):
    raise SystemExit("missing prerequisite diagnostic")
PY

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

# A malformed register is a system error, but the direct gate still retains a
# deterministic admission report for diagnosis.
printf '%s\n' '{"schema":"invalid","cases":[]}' >"$TMP/malformed-cases.json"
MALFORMED_REPORT="$TMP/malformed-support-admission.json"
expect_exit 2 env CORE_CONFORMANCE_CASES="$TMP/malformed-cases.json" \
    swift run tlc-validate core-conformance gate \
    --evidence "$TMP/missing-evidence" \
    --report "$MALFORMED_REPORT" \
    --run-id "$(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --prerequisite available \
    --conformance-exit 0
test -f "$MALFORMED_REPORT"

# Wrapper preflight failures retain reports, and a second run replaces the
# current report reference while retaining both per-run reports.
MISSING_OUTPUT="$TMP/missing-manifest-output"
expect_exit 2 env CORE_CONFORMANCE_CASES="$TMP/not-present.json" "$GATE" --output "$MISSING_OUTPUT"
test -f "$MISSING_OUTPUT/current-support-admission.json"
first_run="$(jq -r .gateRunID "$(current_report "$MISSING_OUTPUT")")"
expect_exit 2 env CORE_CONFORMANCE_CASES="$TMP/not-present.json" "$GATE" --output "$MISSING_OUTPUT"
test -f "$MISSING_OUTPUT/current-support-admission.json"
second_run="$(jq -r .gateRunID "$(current_report "$MISSING_OUTPUT")")"
test "$first_run" != "$second_run"
test -f "$MISSING_OUTPUT/runs/$first_run/support-admission.json"
test -f "$MISSING_OUTPUT/runs/$second_run/support-admission.json"

# A normal-looking setup that leaves the runner unable to execute is still a
# system failure (2), never a semantic block (1), and it retains its report.
FAKE_SETUP="$TMP/fake-setup.sh"
printf '%s\n' '#!/bin/bash' 'exit 0' >"$FAKE_SETUP"
chmod +x "$FAKE_SETUP"
RUNNER_FAILURE_OUTPUT="$TMP/runner-failure-output"
expect_exit 2 env CORE_CONFORMANCE_SETUP_SCRIPT="$FAKE_SETUP" \
    CORE_CONFORMANCE_TOOL_ROOT="$TMP/empty-tool-root" "$GATE" --output "$RUNNER_FAILURE_OUTPUT"
test -f "$RUNNER_FAILURE_OUTPUT/current-support-admission.json"
jq -e '.conformanceExitCode == 2' "$RUNNER_FAILURE_OUTPUT/runs"/*/invocation.json >/dev/null

# A file where the output directory belongs is also retained as a report in a
# sibling failure directory, rather than silently dropping the diagnosis.
OUTPUT_COLLISION="$TMP/output-collision"
printf '%s\n' collision >"$OUTPUT_COLLISION"
expect_exit 2 "$GATE" --output "$OUTPUT_COLLISION"
find "$TMP" -maxdepth 1 -type d -name 'output-collision.failed-*' -exec test -f '{}/current-support-admission.json' \;


echo "core-conformance command checks passed"
