#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUN="$ROOT/scripts/run_core_conformance.sh"
SETUP="$ROOT/scripts/setup-core-conformance-tools.sh"
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

echo "core-conformance command checks passed"
