#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${CORE_CONFORMANCE_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TOOLCHAIN="$PROJECT_ROOT/Verification/CoreConformance/toolchain.json"
TOOL_ROOT="$PROJECT_ROOT/.build/core-conformance-tools"
CASES_FILE="${CORE_CONFORMANCE_CASES:-$PROJECT_ROOT/Verification/CoreConformance/cases.json}"
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
    echo "core-conformance setup: $*" >&2
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
fixtures_root = os.path.join(project_root, "Verification", "CoreConformance", "fixtures")

with open(cases_path, encoding="utf-8") as source:
    manifest = json.load(source)
if manifest.get("schema") != "CoreConformanceCasesV1":
    raise SystemExit("unsupported core-conformance cases schema")

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
        fixtures = case.get("fixtures")
        if fixtures is not None and not isinstance(fixtures, dict):
            raise SystemExit(f"case {case_id} fixtures must be an object")
        source_path = fixtures.get(field) if fixtures else None
        if source_path is None and isinstance(destination_path, str) and destination_path.startswith("fixtures/"):
            source_path = os.path.join("Verification", "CoreConformance", destination_path)
        if source_path is None:
            continue
        source_path = relative_path(source_path, f"fixtures.{field}", case_id)
        source = os.path.realpath(os.path.join(project_root, source_path))
        if os.path.commonpath((fixtures_root, source)) != fixtures_root:
            raise SystemExit(f"case {case_id} {field} fixture is outside retained fixtures")
        if not os.path.isfile(source):
            raise SystemExit(f"case {case_id} {field} fixture is missing: {source_path}")
        destination = staged_path(destination_path, field, case_id)
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(source, destination)
PY
}

if [ "$STAGE_INPUTS_ONLY" = true ]; then
    [ -f "$CASES_FILE" ] || fail "cases manifest is missing: $CASES_FILE"
    stage_declared_inputs "$TOOL_ROOT/inputs"
    printf '%s\n' "CORE_CONFORMANCE_INPUT_ROOT=$TOOL_ROOT/inputs"
    exit 0
fi

[ -f "$TOOLCHAIN" ] || fail "toolchain lock is missing: $TOOLCHAIN"

read_lock() {
    python3 - "$TOOLCHAIN" "$@" <<'PY'
import json
import sys

expected = {
    "schema": "TLCReferencePinV1",
    "tlc.tag": "v1.8.0",
    "tlc.commit": "30cc3601321c3fc02e044d0ecb5c58d8921e18df",
    "tlc.jar.sha256": "e22f8ffb4bacdea0a871f444dd94fe5fb0d8013b3388ae39e82e26f852c735d5",
    "java.distribution": "Eclipse Temurin",
    "java.version": "17.0.19+10",
    "java.archives.arm64.sha256": "8fa1eff40bb637a33613b2ccb8b12c70dc3661cc22cf8e784943715769a05336",
    "java.archives.x86_64.sha256": "03632d1fbf139ab3719a9f4b47dc206251449b87557143c822336dbf8c06560f",
    "bridge.class": "org.swifttla.conformance.LosslessStateWriter",
    "bridge.sourceSha256": "d6a390a1dd8c81e20c22f715a0133f5c7561178a9a5dcdcd7f184c695a6741b7",
    "bridge.binarySha256": "240a717693a5500be4067a3bb4d90fa9c3edce67855f09c5422daf5512ee0fde",
}

with open(sys.argv[1], encoding="utf-8") as source:
    lock = json.load(source)

def get(path):
    value = lock
    for component in path.split("."):
        value = value[component]
    return value

for path, value in expected.items():
    if get(path) != value:
        raise SystemExit(
            "toolchain lock does not match the accepted TLC reference pin: " + path
        )

for path in sys.argv[2:]:
    print(get(path))
PY
}

if ! LOCK_VALUES="$(read_lock tlc.jar.url tlc.jar.sha256 java.archives."$(uname -m)".url java.archives."$(uname -m)".sha256 bridge.source)"; then
    fail "${LOCK_VALUES:-toolchain lock does not match the accepted TLC reference pin}"
fi

ARCHITECTURE="$(uname -m)"
case "$ARCHITECTURE" in
    arm64|x86_64) ;;
    *) fail "unsupported architecture: $ARCHITECTURE" ;;
esac

TLC_URL="$(printf '%s\n' "$LOCK_VALUES" | sed -n '1p')"
TLC_SHA256="$(printf '%s\n' "$LOCK_VALUES" | sed -n '2p')"
JAVA_URL="$(printf '%s\n' "$LOCK_VALUES" | sed -n '3p')"
JAVA_SHA256="$(printf '%s\n' "$LOCK_VALUES" | sed -n '4p')"
BRIDGE_SOURCE_RELATIVE="$(printf '%s\n' "$LOCK_VALUES" | sed -n '5p')"
BRIDGE_SOURCE="$PROJECT_ROOT/$BRIDGE_SOURCE_RELATIVE"
[ -f "$BRIDGE_SOURCE" ] || fail "bridge source is missing: $BRIDGE_SOURCE_RELATIVE"

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

download_locked() {
    local url="$1"
    local digest="$2"
    local destination="$3"
    if [ -f "$destination" ] && [ "$(sha256 "$destination")" = "$digest" ]; then
        return
    fi
    rm -f "$destination"
    local temporary="$destination.partial"
    rm -f "$temporary"
    curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error --output "$temporary" "$url"
    [ "$(sha256 "$temporary")" = "$digest" ] || { rm -f "$temporary"; fail "digest mismatch for $(basename "$destination")"; }
    mv "$temporary" "$destination"
}

mkdir -p "$TOOL_ROOT/downloads" "$TOOL_ROOT/bridge-classes"
TLC_JAR="$TOOL_ROOT/downloads/tla2tools.jar"
JAVA_ARCHIVE="$TOOL_ROOT/downloads/temurin-${ARCHITECTURE}.tar.gz"
download_locked "$TLC_URL" "$TLC_SHA256" "$TLC_JAR"
download_locked "$JAVA_URL" "$JAVA_SHA256" "$JAVA_ARCHIVE"
[ "$(sha256 "$BRIDGE_SOURCE")" = "d6a390a1dd8c81e20c22f715a0133f5c7561178a9a5dcdcd7f184c695a6741b7" ] || fail "bridge source digest mismatch"

JAVA_HOME="$TOOL_ROOT/java-${ARCHITECTURE}/Contents/Home"
if [ ! -x "$JAVA_HOME/bin/javac" ]; then
    rm -rf "$TOOL_ROOT/java-${ARCHITECTURE}"
    mkdir -p "$TOOL_ROOT/java-${ARCHITECTURE}"
    tar -xzf "$JAVA_ARCHIVE" -C "$TOOL_ROOT/java-${ARCHITECTURE}" --strip-components=1
fi
[ -x "$JAVA_HOME/bin/javac" ] || fail "locked Temurin archive does not contain javac"

BRIDGE_CLASS="$TOOL_ROOT/bridge-classes/org/swifttla/conformance/LosslessStateWriter.class"
if [ ! -f "$BRIDGE_CLASS" ] || [ "$(sha256 "$BRIDGE_CLASS")" != "240a717693a5500be4067a3bb4d90fa9c3edce67855f09c5422daf5512ee0fde" ]; then
    rm -rf "$TOOL_ROOT/bridge-classes"
    mkdir -p "$TOOL_ROOT/bridge-classes"
    "$JAVA_HOME/bin/javac" --release 17 -cp "$TLC_JAR" -d "$TOOL_ROOT/bridge-classes" "$BRIDGE_SOURCE"
fi
[ "$(sha256 "$BRIDGE_CLASS")" = "240a717693a5500be4067a3bb4d90fa9c3edce67855f09c5422daf5512ee0fde" ] || fail "bridge binary digest mismatch"

if [ -f "$CASES_FILE" ]; then
    INPUT_ROOT="$TOOL_ROOT/inputs"
    python3 - "$CASES_FILE" "$INPUT_ROOT" <<'PY'
import json
import os
import subprocess
import sys

cases_path, input_root = sys.argv[1:]
with open(cases_path, encoding="utf-8") as source:
    manifest = json.load(source)
if manifest.get("schema") != "CoreConformanceCasesV1":
    raise SystemExit("unsupported core-conformance cases schema")
for case in manifest.get("cases", []):
    upstream = case.get("upstream")
    if upstream is None:
        continue
    repository = upstream.get("repository")
    commit = upstream.get("commit")
    identifier = case.get("id")
    if not all(isinstance(value, str) and value for value in (repository, commit, identifier)):
        raise SystemExit("case upstream identity is incomplete")
    destination = os.path.join(input_root, identifier)
    if os.path.isdir(os.path.join(destination, ".git")):
        head = subprocess.check_output(["git", "-C", destination, "rev-parse", "HEAD"], text=True).strip()
        if head == commit:
            continue
        raise SystemExit("existing upstream checkout has an unexpected commit: " + identifier)
    if os.path.exists(destination):
        raise SystemExit("upstream input path already exists and is not a locked checkout: " + identifier)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    subprocess.run(["git", "init", "--quiet", destination], check=True)
    subprocess.run(["git", "-C", destination, "remote", "add", "origin", repository], check=True)
    subprocess.run(["git", "-C", destination, "fetch", "--quiet", "--depth", "1", "origin", commit], check=True)
    subprocess.run(["git", "-C", destination, "checkout", "--quiet", "--detach", "FETCH_HEAD"], check=True)
PY
    stage_declared_inputs "$INPUT_ROOT"
fi

printf '%s\n' "CORE_CONFORMANCE_TOOL_ROOT=$TOOL_ROOT"
