#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SETUP="$ROOT/scripts/setup-finite-graph-tools.sh"
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

python3 - "$ROOT/Verification/FiniteGraph/toolchain.json" "$TMP/toolchain.json" <<'PY'
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

mkdir -p "$TMP/project/Verification/FiniteGraph/fixtures/local" "$TMP/tool-root"
printf '%s\n' '---- MODULE LocalFixture ----' '====' >"$TMP/project/Verification/FiniteGraph/fixtures/local/LocalFixture.tla"
printf '%s\n' 'SPECIFICATION Spec' >"$TMP/project/Verification/FiniteGraph/fixtures/local/LocalFixture.cfg"
printf '%s\n' '---- MODULE LocalImport ----' '====' >"$TMP/project/Verification/FiniteGraph/fixtures/local/LocalImport.tla"
cat >"$TMP/local-fixtures.json" <<JSON
{
  "schema": "FiniteGraphCases",
  "cases": [{
    "id": "local-fixture",
    "module": "local/LocalFixture.tla",
    "configuration": "local/LocalFixture.cfg",
    "imports": ["local/LocalImport.tla"],
    "dependencies": [{
      "importingModule": "LocalFixture",
      "importedModule": "LocalImport"
    }]
  }]
}
JSON
FINITE_GRAPH_PROJECT_ROOT="$TMP/project" "$SETUP" --cases "$TMP/local-fixtures.json" --tool-root "$TMP/tool-root" --stage-inputs-only >/dev/null
cmp "$TMP/project/Verification/FiniteGraph/fixtures/local/LocalFixture.tla" "$TMP/tool-root/inputs/local/LocalFixture.tla"
cmp "$TMP/project/Verification/FiniteGraph/fixtures/local/LocalFixture.cfg" "$TMP/tool-root/inputs/local/LocalFixture.cfg"
cmp "$TMP/project/Verification/FiniteGraph/fixtures/local/LocalImport.tla" "$TMP/tool-root/inputs/local/LocalImport.tla"

python3 - "$TMP/local-fixtures.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
manifest["cases"][0]["module"] = "../../outside.tla"
with open(sys.argv[1], "w", encoding="utf-8") as destination:
    json.dump(manifest, destination)
PY
expect_failure "escapes retained fixtures" \
    env FINITE_GRAPH_PROJECT_ROOT="$TMP/project" "$SETUP" --cases "$TMP/local-fixtures.json" --tool-root "$TMP/tool-root" --stage-inputs-only

echo "finite-graph command checks passed"
