#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${FINITE_GRAPH_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TOOLCHAIN="$PROJECT_ROOT/Verification/FiniteGraph/toolchain.json"
TOOL_ROOT="$PROJECT_ROOT/.build/finite-graph-tools"
CASES_FILE="${FINITE_GRAPH_CASES:-$PROJECT_ROOT/Verification/FiniteGraph/cases.json}"
STAGE_INPUTS_ONLY=false

usage() {
    echo "Usage: $0 [--toolchain <path>] [--tool-root <path>] [--cases <path>] [--stage-inputs-only]" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --toolchain) TOOLCHAIN="${2:-}"; shift 2 ;;
        --tool-root) TOOL_ROOT="${2:-}"; shift 2 ;;
        --cases) CASES_FILE="${2:-}"; shift 2 ;;
        --stage-inputs-only) STAGE_INPUTS_ONLY=true; shift ;;
        *) usage ;;
    esac
done

fail() {
    echo "finite-graph setup: $*" >&2
    exit 2
}

stage_declared_inputs() {
    local input_root="$1"
    python3 - "$CASES_FILE" "$PROJECT_ROOT" "$input_root" <<'PY'
import json
import os
import shutil
import sys

cases_path, project_root, input_root = map(os.path.realpath, sys.argv[1:])
fixtures_root = os.path.join(project_root, "Verification", "FiniteGraph", "fixtures")

with open(cases_path, encoding="utf-8") as source:
    manifest = json.load(source)
if manifest.get("schema") != "FiniteGraphCases":
    raise SystemExit("unsupported finite-graph cases schema")

def relative_path(value, field, case_id):
    if not isinstance(value, str) or not value or os.path.isabs(value):
        raise SystemExit(f"case {case_id} has invalid {field} path")
    return value

def staged_path(value, field, case_id):
    destination = os.path.realpath(os.path.join(input_root, relative_path(value, field, case_id)))
    if os.path.commonpath((input_root, destination)) != input_root:
        raise SystemExit(f"case {case_id} {field} path escapes the staged input root")
    return destination

for case in manifest.get("cases", []):
    case_id = case.get("id")
    if not isinstance(case_id, str) or not case_id:
        raise SystemExit("case identifier is incomplete")
    for field in ("module", "configuration"):
        destination_path = case.get(field)
        source = os.path.realpath(os.path.join(fixtures_root, relative_path(destination_path, field, case_id)))
        if os.path.commonpath((fixtures_root, source)) != fixtures_root:
            raise SystemExit(f"case {case_id} {field} escapes retained fixtures")
        if not os.path.isfile(source):
            raise SystemExit(f"case {case_id} {field} fixture is missing: {destination_path}")
        destination = staged_path(destination_path, field, case_id)
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(source, destination)
    imports = case.get("imports")
    if not isinstance(imports, list) or not all(isinstance(value, str) and value for value in imports):
        raise SystemExit(f"case {case_id} imports must be an array of non-empty strings")
    for index, destination_path in enumerate(imports):
        field = f"imports[{index}]"
        source = os.path.realpath(os.path.join(fixtures_root, relative_path(destination_path, field, case_id)))
        if os.path.commonpath((fixtures_root, source)) != fixtures_root:
            raise SystemExit(f"case {case_id} {field} escapes retained fixtures")
        if not os.path.isfile(source):
            raise SystemExit(f"case {case_id} {field} fixture is missing: {destination_path}")
        destination = staged_path(destination_path, field, case_id)
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(source, destination)
PY
}

if [ "$STAGE_INPUTS_ONLY" = true ]; then
    [ -f "$CASES_FILE" ] || fail "cases manifest is missing: $CASES_FILE"
    stage_declared_inputs "$TOOL_ROOT/inputs"
    printf '%s\n' "FINITE_GRAPH_INPUT_ROOT=$TOOL_ROOT/inputs"
    exit 0
fi

[ -f "$TOOLCHAIN" ] || fail "toolchain lock is missing: $TOOLCHAIN"

read_lock() {
    python3 - "$TOOLCHAIN" "$@" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    lock = json.load(source)

def get(path):
    value = lock
    for component in path.split("."):
        value = value[component]
    return value

required = [
    "tlc.tag", "tlc.commit", "tlc.jar.repository", "tlc.jar.sha256", "tlc.jar.archiveSHA256", "tlc.jar.buildRevision",
    "java.distribution", "java.version",
    "java.archives.arm64.url", "java.archives.arm64.sha256",
    "java.archives.x86_64.url", "java.archives.x86_64.sha256",
    "bridge.class",
]
if lock.get("schema") != "TLCReferencePin":
    raise SystemExit("unsupported toolchain schema")
for path in required:
    value = get(path)
    if not isinstance(value, str) or not value:
        raise SystemExit("toolchain lock has an invalid value: " + path)

for path in ["tlc.jar.artifactID", "tlc.jar.buildRunID"]:
    value = get(path)
    if type(value) is not int or value <= 0:
        raise SystemExit("toolchain lock has an invalid value: " + path)
for path, length in [("tlc.commit", 40), ("tlc.jar.buildRevision", 40),
                     ("tlc.jar.sha256", 64), ("tlc.jar.archiveSHA256", 64)]:
    if not re.fullmatch("[0-9a-f]{" + str(length) + "}", get(path)):
        raise SystemExit("toolchain lock has an invalid value: " + path)

for path in sys.argv[2:]:
    print(get(path))
PY
}

if ! LOCK_VALUES="$(read_lock tlc.jar.repository tlc.jar.artifactID tlc.jar.sha256 java.archives."$(uname -m)".url java.archives."$(uname -m)".sha256 tlc.jar.archiveSHA256 tlc.commit)"; then
    fail "${LOCK_VALUES:-toolchain lock does not match the accepted TLC reference pin}"
fi

ARCHITECTURE="$(uname -m)"
case "$ARCHITECTURE" in
    arm64|x86_64) ;;
    *) fail "unsupported architecture: $ARCHITECTURE" ;;
esac

TLC_REPOSITORY="$(printf '%s\n' "$LOCK_VALUES" | sed -n '1p')"
TLC_ARTIFACT_ID="$(printf '%s\n' "$LOCK_VALUES" | sed -n '2p')"
TLC_ARTIFACT_URL="https://api.github.com/repos/$TLC_REPOSITORY/actions/artifacts/$TLC_ARTIFACT_ID/zip"
TLC_SHA256="$(printf '%s\n' "$LOCK_VALUES" | sed -n '3p')"
JAVA_URL="$(printf '%s\n' "$LOCK_VALUES" | sed -n '4p')"
JAVA_SHA256="$(printf '%s\n' "$LOCK_VALUES" | sed -n '5p')"
TLC_ARCHIVE_SHA256="$(printf '%s\n' "$LOCK_VALUES" | sed -n '6p')"
TLC_SOURCE_REVISION="$(printf '%s\n' "$LOCK_VALUES" | sed -n '7p')"

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

download_locked() {
    local url="$1"
    local digest="$2"
    local destination="$3"
    shift 3
    if [ -f "$destination" ] && [ "$(sha256 "$destination")" = "$digest" ]; then
        return
    fi
    rm -f "$destination"
    local temporary="$destination.partial"
    rm -f "$temporary"
    curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error \
        --retry 3 --retry-max-time 60 \
        --output "$temporary" "$@" --url "$url"
    [ "$(sha256 "$temporary")" = "$digest" ] || { rm -f "$temporary"; fail "digest mismatch for $(basename "$destination")"; }
    mv "$temporary" "$destination"
}

seed_from_cache() {
    local cache_file="$1"
    local digest="$2"
    local destination="$3"
    if [ -f "$destination" ] || [ ! -f "$cache_file" ]; then
        return
    fi
    if [ "$(sha256 "$cache_file")" = "$digest" ]; then
        cp "$cache_file" "$destination"
    fi
}

mkdir -p "$TOOL_ROOT/downloads" "$TOOL_ROOT/bridge-classes"
TLC_JAR="$TOOL_ROOT/downloads/tla2tools.jar"
JAVA_ARCHIVE="$TOOL_ROOT/downloads/temurin-${ARCHITECTURE}.tar.gz"
CACHE_ROOT="$PROJECT_ROOT/Tools/TLCGraphBridge/.tool-cache"
seed_from_cache "$CACHE_ROOT/OpenJDK17U-jdk_${ARCHITECTURE}_mac_hotspot_17.0.19_10.tar.gz" "$JAVA_SHA256" "$JAVA_ARCHIVE"
TLC_HEADERS=(
    --header 'Accept: application/vnd.github+json'
    --header 'X-GitHub-Api-Version: 2022-11-28'
)
if [ -n "${FINITE_GRAPH_GITHUB_TOKEN:-}" ]; then
    TLC_HEADERS+=(--header "Authorization: Bearer $FINITE_GRAPH_GITHUB_TOKEN")
fi
# ponytail: retained artifacts expire; rebuild and explicitly repin instead of using a moving release.
TLC_ARCHIVE="$TOOL_ROOT/downloads/tlc-reference-build.zip"
download_locked "$TLC_ARTIFACT_URL" "$TLC_ARCHIVE_SHA256" "$TLC_ARCHIVE" "${TLC_HEADERS[@]}"
python3 - "$TLC_ARCHIVE" "$TLC_JAR" "$TLC_SHA256" "$TLC_SOURCE_REVISION" <<'PY'
import hashlib
import sys
import zipfile

archive_path, jar_path, expected_digest, expected_revision = sys.argv[1:]
with zipfile.ZipFile(archive_path) as archive:
    for name in ["tla2tools.jar", "source-revision.txt"]:
        if archive.namelist().count(name) != 1:
            raise SystemExit("TLC build archive requires exactly one " + name)
    if archive.read("source-revision.txt").decode("utf-8").strip() != expected_revision:
        raise SystemExit("TLC build archive source revision differs from the toolchain lock")
    jar = archive.read("tla2tools.jar")
if hashlib.sha256(jar).hexdigest() != expected_digest:
    raise SystemExit("TLC build archive JAR digest differs from the toolchain lock")
with open(jar_path, "wb") as destination:
    destination.write(jar)
PY
download_locked "$JAVA_URL" "$JAVA_SHA256" "$JAVA_ARCHIVE"
if ! BRIDGE_SOURCE_PATHS="$(python3 - "$PROJECT_ROOT" "$TOOLCHAIN" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
sources = json.loads(Path(sys.argv[2]).read_text())["bridge"]["sources"]
if not isinstance(sources, dict) or not sources:
    raise SystemExit("bridge source inventory is empty")
for relative, digest in sorted(sources.items()):
    source = (root / relative).resolve()
    if not source.is_relative_to(root) or "\n" in str(source) or source.suffix != ".java":
        raise SystemExit("invalid bridge source path: " + relative)
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise SystemExit("bridge source digest mismatch: " + relative)
    print(source)
PY
)"; then
    fail "bridge source validation failed"
fi
BRIDGE_SOURCES=()
while IFS= read -r source; do
    BRIDGE_SOURCES+=("$source")
done <<< "$BRIDGE_SOURCE_PATHS"

python3 - "$TLC_JAR" "$TOOLCHAIN" <<'PY'
from email.parser import Parser
import json
import sys
import zipfile

jar_path, toolchain_path = sys.argv[1:]
with open(toolchain_path, encoding="utf-8") as source:
    reference = json.load(source)["tlc"]
    modules = reference["standardModules"]
with zipfile.ZipFile(jar_path) as jar:
    manifest = Parser().parsestr(jar.read("META-INF/MANIFEST.MF").decode("utf-8"))
    if manifest["X-Git-Revision"] != reference["commit"]:
        raise SystemExit("TLC JAR source revision differs from the toolchain lock")
    actual = sorted(
        name.removeprefix("tla2sany/StandardModules/").removesuffix(".tla")
        for name in jar.namelist()
        if name.startswith("tla2sany/StandardModules/") and name.endswith(".tla")
    )
if modules != actual:
    raise SystemExit("TLC JAR standard-module inventory differs from the toolchain lock")
PY

JAVA_HOME="$TOOL_ROOT/java-${ARCHITECTURE}/Contents/Home"
if [ ! -x "$JAVA_HOME/bin/javac" ]; then
    rm -rf "$TOOL_ROOT/java-${ARCHITECTURE}"
    mkdir -p "$TOOL_ROOT/java-${ARCHITECTURE}"
    tar -xzf "$JAVA_ARCHIVE" -C "$TOOL_ROOT/java-${ARCHITECTURE}" --strip-components=1
fi
[ -x "$JAVA_HOME/bin/javac" ] || fail "locked Temurin archive does not contain javac"

BRIDGE_CLASS="$TOOL_ROOT/bridge-classes/org/swifttla/conformance/LosslessStateWriter.class"
# The bridge is built from pinned inputs; record its output digest in each run.
rm -rf "$TOOL_ROOT/bridge-classes"
mkdir -p "$TOOL_ROOT/bridge-classes"
"$JAVA_HOME/bin/javac" --release 17 -cp "$TLC_JAR" -d "$TOOL_ROOT/bridge-classes" "${BRIDGE_SOURCES[@]}"
[ -f "$BRIDGE_CLASS" ] || fail "bridge compilation produced no class"
"$JAVA_HOME/bin/jar" --create --file "$TOOL_ROOT/bridge.jar" -C "$TOOL_ROOT/bridge-classes" .
python3 "$PROJECT_ROOT/Tools/TLCGraphBridge/check-configuration-parser.py" \
    "$JAVA_HOME/bin/java" "$TLC_JAR" "$TOOL_ROOT/bridge.jar"
if [ "${GITHUB_ACTIONS:-}" = true ]; then
    python3 "$PROJECT_ROOT/Tools/TLCGraphBridge/check-instance-actions.py" \
        "$JAVA_HOME/bin/java" "$TLC_JAR" "$TOOL_ROOT/bridge.jar"
fi

if [ -f "$CASES_FILE" ]; then
    stage_declared_inputs "$TOOL_ROOT/inputs"
fi

printf '%s\n' "FINITE_GRAPH_TOOL_ROOT=$TOOL_ROOT"
