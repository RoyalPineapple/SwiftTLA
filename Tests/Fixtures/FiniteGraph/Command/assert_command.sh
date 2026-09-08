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

mkdir -p "$TMP/project/Verification/FiniteGraph/fixtures/local" "$TMP/tool-root"
printf '%s\n' '---- MODULE LocalFixture ----' '====' >"$TMP/project/Verification/FiniteGraph/fixtures/local/LocalFixture.tla"
printf '%s\n' 'SPECIFICATION Spec' >"$TMP/project/Verification/FiniteGraph/fixtures/local/LocalFixture.cfg"
printf '%s\n' '---- MODULE LocalImport ----' '====' >"$TMP/project/Verification/FiniteGraph/fixtures/local/LocalImport.tla"
cat >"$TMP/local-fixtures.json" <<JSON
{
  "schema": "FiniteGraphCases",
  "cases": [{
    "sourceModel": "local-fixture",
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

cp "$ROOT/Verification/FiniteGraph/toolchain.json" "$TMP/invalid-toolchain.json"
python3 - "$TMP/invalid-toolchain.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    toolchain = json.load(source)
toolchain["tlc"]["jar"]["assetID"] = 0
with open(sys.argv[1], "w", encoding="utf-8") as destination:
    json.dump(toolchain, destination)
PY
expect_failure "invalid value: tlc.jar.assetID" \
    "$SETUP" --toolchain "$TMP/invalid-toolchain.json" --tool-root "$TMP/invalid-tools"

mkdir -p "$TMP/option-url-tools/downloads" "$TMP/bin"
: >"$TMP/option-url-tools/downloads/tla2tools.jar"
cp "$ROOT/Verification/FiniteGraph/toolchain.json" "$TMP/option-url-toolchain.json"
python3 - "$TMP/option-url-toolchain.json" "$(uname -m)" \
    "$(shasum -a 256 "$TMP/option-url-tools/downloads/tla2tools.jar" | awk '{print $1}')" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    toolchain = json.load(source)
toolchain["tlc"]["jar"]["sha256"] = sys.argv[3]
toolchain["java"]["archives"][sys.argv[2]]["url"] = "-K"
with open(sys.argv[1], "w", encoding="utf-8") as destination:
    json.dump(toolchain, destination)
PY
cat >"$TMP/bin/curl" <<'SH'
#!/bin/bash
while [ "$#" -gt 0 ]; do
    if [ "$1" = "--url" ] && [ "${2:-}" = "-K" ]; then
        echo "option-shaped URL remained a URL value" >&2
        exit 2
    fi
    shift
done
exit 3
SH
chmod +x "$TMP/bin/curl"
expect_failure "option-shaped URL remained a URL value" \
    env PATH="$TMP/bin:$PATH" "$SETUP" --toolchain "$TMP/option-url-toolchain.json" \
        --tool-root "$TMP/option-url-tools"

echo "finite-graph command checks passed"
