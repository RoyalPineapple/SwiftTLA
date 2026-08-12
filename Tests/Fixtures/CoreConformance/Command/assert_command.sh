#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUN="$ROOT/scripts/run_core_conformance.sh"
SETUP="$ROOT/scripts/setup-core-conformance-tools.sh"
GATE="$ROOT/scripts/run_core_support_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
{"schema":"CoreConformanceCasesV1","cases":[{"id":"hour-clock"}]}
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
cat >"$TMP/local-fixtures.json" <<JSON
{
  "schema": "CoreConformanceCasesV1",
  "cases": [{
    "id": "local-fixture",
    "module": "fixtures/local/LocalFixture.tla",
    "configuration": "fixtures/local/LocalFixture.cfg"
  }]
}
JSON
CORE_CONFORMANCE_PROJECT_ROOT="$TMP/project" "$SETUP" --cases "$TMP/local-fixtures.json" --tool-root "$TMP/tool-root" --stage-inputs-only >/dev/null
cmp "$TMP/project/Verification/CoreConformance/fixtures/local/LocalFixture.tla" "$TMP/tool-root/inputs/fixtures/local/LocalFixture.tla"
cmp "$TMP/project/Verification/CoreConformance/fixtures/local/LocalFixture.cfg" "$TMP/tool-root/inputs/fixtures/local/LocalFixture.cfg"

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
# stable latest report while retaining both per-run reports.
MISSING_OUTPUT="$TMP/missing-manifest-output"
expect_exit 2 env CORE_CONFORMANCE_CASES="$TMP/not-present.json" "$GATE" --output "$MISSING_OUTPUT"
test -f "$MISSING_OUTPUT/support-admission.json"
first_run="$(jq -r .gateRunID "$MISSING_OUTPUT/support-admission.json")"
expect_exit 2 env CORE_CONFORMANCE_CASES="$TMP/not-present.json" "$GATE" --output "$MISSING_OUTPUT"
test -f "$MISSING_OUTPUT/support-admission.json"
second_run="$(jq -r .gateRunID "$MISSING_OUTPUT/support-admission.json")"
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
test -f "$RUNNER_FAILURE_OUTPUT/support-admission.json"
jq -e '.conformanceExitCode == 2' "$RUNNER_FAILURE_OUTPUT/runs"/*/invocation.json >/dev/null

# A file where the output directory belongs is also retained as a report in a
# sibling failure directory, rather than silently dropping the diagnosis.
OUTPUT_COLLISION="$TMP/output-collision"
printf '%s\n' collision >"$OUTPUT_COLLISION"
expect_exit 2 "$GATE" --output "$OUTPUT_COLLISION"
find "$TMP" -maxdepth 1 -type d -name 'output-collision.failed-*' -exec test -f '{}/support-admission.json' \;

# Build a complete, current retained evidence set without running TLC. The
# register deliberately blocks one requested entry, which is a valid evidence
# decision and must therefore return exit 1 rather than exit 2.
GATE_EVIDENCE="$TMP/current-evidence"
mkdir -p "$GATE_EVIDENCE"
cp -R "$ROOT/Verification/CoreConformance/baselines/hour-clock" "$GATE_EVIDENCE/hour-clock"
cp -R "$ROOT/Verification/CoreConformance/baselines/die-hard-type-ok" "$GATE_EVIDENCE/die-hard-type-ok"
cp -R "$ROOT/Verification/CoreConformance/fixtures/hour-clock-edge-mismatch/evidence" \
    "$GATE_EVIDENCE/hour-clock-edge-mismatch"
cp -R "$ROOT/Verification/CoreConformance/fixtures/die-hard-violation/evidence" \
    "$GATE_EVIDENCE/die-hard-violation"
BLOCKED_RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
python3 - "$ROOT/Verification/CoreConformance/cases.json" "$GATE_EVIDENCE" "$BLOCKED_RUN_ID" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest = {entry["id"]: entry for entry in json.load(open(sys.argv[1], encoding="utf-8"))["cases"]}
root = pathlib.Path(sys.argv[2])
run_id = sys.argv[3]

def write(path, value):
    path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")), encoding="utf-8")

for case_id, declared in manifest.items():
    directory = root / case_id
    toolchain = json.load(open(directory / "toolchain.json", encoding="utf-8"))
    pin = toolchain["declaredPin"]
    governance = declared["governance"]
    runner = {"caseID": case_id, "engine": "runner", "runID": run_id}
    write(directory / "case.json", {
        "id": case_id,
        "moduleSHA256": declared["moduleSHA256"],
        "cfgSHA256": declared["cfgSHA256"],
        "arguments": declared["arguments"],
        "argumentsSHA256": declared["argumentsSHA256"],
        "workers": declared["workers"],
        "fingerprintPolynomial": declared["fingerprintPolynomial"],
        "deadlock": declared["deadlock"],
        "operatingSystem": "macos",
        "architecture": "arm64",
        "environment": {},
        "pin": pin,
        "governance": governance,
    })
    write(directory / "arguments.json", {"arguments": declared["arguments"]})
    write(directory / "correlations.json", {
        "swift": {"caseID": case_id, "engine": "swift", "runID": run_id},
        "tlc": {"caseID": case_id, "engine": "tlc", "runID": run_id},
        "runner": runner,
    })
    write(directory / "run.json", {
        "correlation": runner,
        "exitCode": 0 if governance["expectedRegressionOutcome"] == "exact" else 1,
    })
    for name, engine in (("swift.json", "swift"), ("tlc.json", "tlc"), ("comparison.json", "runner"), ("tlc-process.json", "tlc")):
        path = directory / name
        value = json.load(open(path, encoding="utf-8"))
        value["correlation"] = {"caseID": case_id, "engine": engine, "runID": run_id}
        write(path, value)
    provenance = {
        "tlcTag": pin["tag"], "tlcCommit": pin["commit"], "tlcJarSha256": pin["jarSHA256"],
        "javaDistribution": pin["javaDistribution"], "javaVersion": pin["javaVersion"],
        "javaArchiveSha256": pin["javaArchiveSHA256"], "bridgeClass": pin["bridgeClass"],
        "bridgeSourceSha256": pin["bridgeSourceSHA256"], "bridgeBinarySha256": pin["bridgeBinarySHA256"],
        "moduleSha256": declared["moduleSHA256"], "cfgSha256": declared["cfgSHA256"],
        "arguments": declared["arguments"], "argumentsSha256": declared["argumentsSHA256"],
        "workers": declared["workers"], "fingerprintPolynomial": declared["fingerprintPolynomial"],
        "deadlock": declared["deadlock"], "os": "macos", "architecture": "arm64", "environment": {},
    }
    for name in ("graph-events.jsonl", "graph-events.trace.jsonl", "graph-events.replay.jsonl"):
        path = directory / name
        if not path.exists():
            continue
        records = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
        for record in records:
            record["caseId"] = case_id
            record["runId"] = run_id
        records[0]["provenance"] = provenance
        body = b"".join(json.dumps(record, sort_keys=True, separators=(",", ":")).encode() + b"\n" for record in records[:-1])
        records[-1]["bodySha256"] = hashlib.sha256(body).hexdigest()
        path.write_bytes(b"".join(json.dumps(record, sort_keys=True, separators=(",", ":")).encode() + b"\n" for record in records))
PY
BLOCKED_SURFACE="$TMP/blocked-support-surface.json"
python3 - "$ROOT/Verification/CoreConformance/support-surface.json" "$BLOCKED_SURFACE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    surface = json.load(source)
for entry in surface["entries"]:
    if entry["id"] == "hour-clock-reachable-state-space":
        entry["requestedStatus"] = "blocked"
        entry["reason"] = "shell exit-contract control"
with open(sys.argv[2], "w", encoding="utf-8") as destination:
    json.dump(surface, destination)
PY
VALID_BLOCK_REPORT="$TMP/valid-block-support-admission.json"
expect_exit 1 env CORE_CONFORMANCE_CASES="$ROOT/Verification/CoreConformance/cases.json" \
    CORE_CONFORMANCE_SUPPORT_SURFACE="$BLOCKED_SURFACE" \
    swift run tlc-validate core-conformance gate \
    --evidence "$GATE_EVIDENCE" \
    --report "$VALID_BLOCK_REPORT" \
    --run-id "$BLOCKED_RUN_ID" \
    --prerequisite available \
    --conformance-exit 0
test -f "$VALID_BLOCK_REPORT"
jq -e '.finalExitClass == "blocked"' "$VALID_BLOCK_REPORT" >/dev/null

echo "core-conformance command checks passed"
