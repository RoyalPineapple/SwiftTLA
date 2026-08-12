#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_PACKAGE="$PROJECT_ROOT/Packages/SwiftTLAVerified"
OUTPUT=""
CONTEXT=""
HOSTED_CI=false
PACKAGE_PATH="${PUBLIC_WORKFLOW_PLATFORM_PACKAGE_PATH:-$DEFAULT_PACKAGE}"
XCODEBUILD="${PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD:-xcodebuild}"
SCHEME="${PUBLIC_WORKFLOW_PLATFORM_SCHEME:-SwiftTLAVerified-Package}"
MATRIX="${PUBLIC_WORKFLOW_PLATFORM_MATRIX:-macos|macosx|platform=macOS|test|;ios|iphoneos|generic/platform=iOS|build|SwiftTLAVerified;mac-catalyst|macosx|platform=macOS,variant=Mac Catalyst|build|SwiftTLAVerified;tvos|appletvos|generic/platform=tvOS|build|SwiftTLAVerified;watchos|watchos|generic/platform=watchOS|build|SwiftTLAVerified}"

usage() {
    echo "Usage: $0 --output <directory> --context <binding-context.json> [--hosted-ci]" >&2
    exit 2
}

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

tree_digest() {
    local root="$1"
    if [ ! -d "$root" ]; then
        printf 'missing'
        return
    fi
    (
        cd "$root"
        find . -type f -not -path './.build/*' -not -path './.swiftpm/*' -print0 \
            | LC_ALL=C sort -z \
            | while IFS= read -r -d '' path; do
                printf '%s %s\n' "$(sha256 "$path")" "$path"
            done \
            | shasum -a 256 \
            | awk '{print $1}'
    )
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) [ -z "$OUTPUT" ] || usage; OUTPUT="${2:-}"; shift 2 ;;
        --context) [ -z "$CONTEXT" ] || usage; CONTEXT="${2:-}"; shift 2 ;;
        --hosted-ci) HOSTED_CI=true; shift ;;
        *) usage ;;
    esac
done
[ -n "$OUTPUT" ] && [ -n "$CONTEXT" ] || usage
[ -f "$CONTEXT" ] || { echo "public-workflow platform matrix: binding context is missing: $CONTEXT" >&2; exit 2; }

read_context() {
    python3 - "$CONTEXT" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
required = {"caseID", "gateRunID", "sourceInput", "configuration", "provenance"}
if set(value) != required:
    raise SystemExit("binding context must contain exactly caseID, gateRunID, sourceInput, configuration, provenance")
for field in ("sourceInput", "configuration"):
    reference = value[field]
    if (set(reference) != {"path", "sha256"} or not reference["path"] or reference["path"].startswith("/")
            or not isinstance(reference["sha256"], str) or len(reference["sha256"]) != 64
            or set(reference["sha256"]) == {"0"}):
        raise SystemExit(f"binding context has invalid {field}")
if not value["caseID"] or not value["gateRunID"]:
    raise SystemExit("binding context has no case or gate run identity")
for key, digest in value["provenance"].items():
    if key.endswith("SHA256") and (not isinstance(digest, str) or len(digest) != 64 or set(digest) == {"0"}):
        raise SystemExit(f"binding context has incomplete provenance digest {key}")
print(json.dumps(value, sort_keys=True, separators=(",", ":")))
PY
}

CONTEXT_JSON="$(read_context)" || { echo "public-workflow platform matrix: invalid binding context" >&2; exit 2; }
if ! python3 - "$CONTEXT" "$PROJECT_ROOT" <<'PY'
import hashlib
import json
import pathlib
import sys

context = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
root = pathlib.Path(sys.argv[2])
for field in ("sourceInput", "configuration"):
    reference = context[field]
    target = root / reference["path"]
    if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != reference["sha256"]:
        raise SystemExit(f"binding context {field} is missing or digest-mismatched")
provenance = context["provenance"]
if provenance["caseID"] != context["caseID"] or provenance["moduleSHA256"] != context["sourceInput"]["sha256"] or provenance["cfgSHA256"] != context["configuration"]["sha256"]:
    raise SystemExit("binding context provenance does not bind declared inputs")
PY
then
    echo "public-workflow platform matrix: context inputs are not reproducibly bound" >&2
    exit 2
fi

if ! python3 - "$CONTEXT" "$MATRIX" "$SCHEME" <<'PY'
import hashlib
import json
import sys

context = json.loads(open(sys.argv[1], encoding="utf-8").read())
matrix, scheme = sys.argv[2:]
commands = []
for entry in matrix.split(";"):
    platform, sdk, destination, action, target = (entry.split("|") + [""])[:5]
    command = ["xcodebuild", "-scheme", scheme]
    if target:
        command.extend(["-target", target])
    command.extend(["-sdk", sdk, "-destination", destination, action])
    commands.append(command)
digest = hashlib.sha256(json.dumps(commands, separators=(",", ":")).encode()).hexdigest()
if context["provenance"]["argumentsSHA256"] != digest:
    raise SystemExit("binding context arguments digest does not match declared xcodebuild invocation")
PY
then
    echo "public-workflow platform matrix: command digest does not match the declared invocation" >&2
    exit 2
fi

RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
REPORT_ROOT="$OUTPUT"
if [ -e "$OUTPUT" ] && [ ! -d "$OUTPUT" ]; then
    REPORT_ROOT="${OUTPUT}.failed-${RUN_ID}"
fi
RUN_ROOT="$REPORT_ROOT/runs/$RUN_ID"
RESULTS_ROOT="$RUN_ROOT/platforms"
mkdir -p "$RESULTS_ROOT"

PACKAGE_MANIFEST="$PACKAGE_PATH/Package.swift"
PACKAGE_RESOLVED="$PACKAGE_PATH/Package.resolved"
PACKAGE_TREE_SHA256="$(tree_digest "$PACKAGE_PATH")"
PACKAGE_MANIFEST_SHA256="missing"
PACKAGE_RESOLVED_SHA256="missing"
[ -f "$PACKAGE_MANIFEST" ] && PACKAGE_MANIFEST_SHA256="$(sha256 "$PACKAGE_MANIFEST")"
[ -f "$PACKAGE_RESOLVED" ] && PACKAGE_RESOLVED_SHA256="$(sha256 "$PACKAGE_RESOLVED")"

TOOLCHAIN_LOG="$RUN_ROOT/toolchain.log"
TOOLCHAIN_STATUS=0
set +e
"$XCODEBUILD" -version >"$TOOLCHAIN_LOG" 2>&1
TOOLCHAIN_STATUS=$?
set -e
TOOLCHAIN_SHA256="$(sha256 "$TOOLCHAIN_LOG")"
XCODE_VERSION="$(sed -n '1{s/[[:space:]]*$//;p;}' "$TOOLCHAIN_LOG")"
[ -n "$XCODE_VERSION" ] || XCODE_VERSION="unavailable"

EXECUTION_METADATA="$RUN_ROOT/ci-execution.json"
python3 - "$EXECUTION_METADATA" "$TOOLCHAIN_LOG" "$TOOLCHAIN_SHA256" "$HOSTED_CI" <<'PY'
import json
import os
import pathlib
import sys

output, toolchain_log, toolchain_sha, hosted_ci = sys.argv[1:]
fields = {
    "gitSHA": os.environ.get("GITHUB_SHA"),
    "repository": os.environ.get("GITHUB_REPOSITORY"),
    "workflow": os.environ.get("GITHUB_WORKFLOW"),
    "ref": os.environ.get("GITHUB_REF"),
    "runID": os.environ.get("GITHUB_RUN_ID"),
    "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    "job": os.environ.get("GITHUB_JOB"),
    "serverURL": os.environ.get("GITHUB_SERVER_URL"),
}
complete = hosted_ci == "true" and os.environ.get("GITHUB_ACTIONS") == "true" and all(fields.values())
value = {
    "authority": "candidate" if complete else "diagnostic",
    "githubActions": os.environ.get("GITHUB_ACTIONS") == "true",
    "identity": fields if complete else None,
    "toolchainLog": toolchain_log,
    "toolchainSHA256": toolchain_sha,
    "admission": "hosted workflow evidence for declared bounded checks" if complete else "local diagnostic only",
}
pathlib.Path(output).write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY

write_result() {
    local result="$1"
    local platform="$2"
    local sdk="$3"
    local destination="$4"
    local action="$5"
    local status="$6"
    local diagnostic="$7"
    local exit_code="$8"
    local stdout="$9"
    local stderr="${10}"
    local command="${11}"
    local fixture="${12}"
    python3 - "$result" "$PROJECT_ROOT" "$CONTEXT_JSON" "$RUN_ID" "$platform" "$sdk" "$destination" "$action" "$status" "$diagnostic" "$exit_code" "$stdout" "$stderr" "$command" "$TOOLCHAIN_LOG" "$TOOLCHAIN_STATUS" "$TOOLCHAIN_SHA256" "$XCODE_VERSION" "$PACKAGE_PATH" "$PACKAGE_MANIFEST" "$PACKAGE_MANIFEST_SHA256" "$PACKAGE_RESOLVED" "$PACKAGE_RESOLVED_SHA256" "$PACKAGE_TREE_SHA256" "$fixture" "$EXECUTION_METADATA" <<'PY'
import json
import hashlib
import pathlib
import sys

(path, project_root, context_json, matrix_run_id, platform, sdk, destination, action, status, diagnostic, exit_code,
 stdout, stderr, command, toolchain_log, toolchain_exit, toolchain_sha, xcode_version,
 package, manifest, manifest_sha, resolved, resolved_sha, tree_sha, fixture, execution_metadata) = sys.argv[1:]

context = json.loads(context_json)
root = pathlib.Path(project_root).resolve()
def reference(target):
    target = pathlib.Path(target)
    return {
        "path": str(target.resolve().relative_to(root)),
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }

platform_run_id = __import__("uuid").uuid4()
fixture_ref = reference(fixture)
stdout_ref = reference(stdout)
stderr_ref = reference(stderr)
execution_metadata_ref = reference(execution_metadata)
execution_data = json.loads(pathlib.Path(execution_metadata).read_text(encoding="utf-8"))
identity = execution_data["identity"]
execution = {
    "authority": execution_data["authority"],
    "gitSHA": identity["gitSHA"] if identity else None,
    "repository": identity["repository"] if identity else None,
    "workflow": identity["workflow"] if identity else None,
    "ref": identity["ref"] if identity else None,
    "runID": identity["runID"] if identity else None,
    "runAttempt": int(identity["runAttempt"]) if identity else None,
    "job": identity["job"] if identity else None,
    "serverURL": identity["serverURL"] if identity else None,
    "metadata": execution_metadata_ref,
}
def binding(evidence):
    return {
        "caseID": context["caseID"],
        "gateRunID": context["gateRunID"],
        "evidenceRunID": str(platform_run_id),
        "sourceInput": context["sourceInput"],
        "configuration": context["configuration"],
        "provenance": context["provenance"],
        "evidence": evidence,
    }

value = {
    "platform": platform,
    "command": command,
    "sdk": sdk,
    "destination": destination,
    "xcodeVersion": xcode_version,
    "fixture": fixture_ref,
    "status": status,
    "exitCode": int(exit_code) if status != "unavailable" else None,
    "stdout": stdout_ref,
    "stderr": stderr_ref,
    "correlation": {"caseID": context["caseID"], "gateRunID": context["gateRunID"], "platformRunID": str(platform_run_id)},
    "fixtureBinding": binding(fixture_ref),
    "stdoutBinding": binding(stdout_ref),
    "stderrBinding": binding(stderr_ref),
    "execution": execution,
}
pathlib.Path(path).write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY
}

overall_exit=0
IFS=';' read -r -a entries <<< "$MATRIX"
for entry in "${entries[@]}"; do
    IFS='|' read -r platform sdk destination action target <<< "$entry"
    [ -n "${platform:-}" ] && [ -n "${sdk:-}" ] && [ -n "${destination:-}" ] && [ -n "${action:-}" ] || {
        echo "public-workflow platform matrix: invalid matrix entry: $entry" >&2
        exit 2
    }

    platform_root="$RESULTS_ROOT/$platform"
    mkdir -p "$platform_root"
    stdout="$platform_root/stdout.log"
    stderr="$platform_root/stderr.log"
    result="$platform_root/result.json"
    fixture="$platform_root/input-manifest.json"
    derived_data="$RUN_ROOT/derived-data/$platform"
    command="cd $PACKAGE_PATH && $XCODEBUILD -scheme $SCHEME ${target:+-target $target }-sdk $sdk -destination $destination -derivedDataPath $derived_data $action"
    status="failed"
    diagnostic="xcodebuild-failed"
    exit_code=0

    python3 - "$fixture" "$PROJECT_ROOT" "$PACKAGE_PATH" "$PACKAGE_MANIFEST" "$PACKAGE_MANIFEST_SHA256" "$PACKAGE_RESOLVED" "$PACKAGE_RESOLVED_SHA256" "$PACKAGE_TREE_SHA256" "$TOOLCHAIN_LOG" "$TOOLCHAIN_SHA256" "$command" "$derived_data" <<'PY'
import hashlib
import json
import pathlib
import sys

(output, project_root, package, manifest, manifest_sha, resolved, resolved_sha, tree_sha, toolchain, toolchain_sha, command, derived_data) = sys.argv[1:]
root = pathlib.Path(project_root).resolve()
def portable_path(path):
    target = pathlib.Path(path).resolve()
    try:
        return str(target.relative_to(root))
    except ValueError:
        return str(target)
value = {
    "packagePath": portable_path(package),
    "packageManifest": portable_path(manifest),
    "packageManifestSHA256": manifest_sha,
    "packageResolved": portable_path(resolved),
    "packageResolvedSHA256": resolved_sha,
    "packageTreeSHA256": tree_sha,
    "toolchainLog": portable_path(toolchain),
    "toolchainSHA256": toolchain_sha,
    "workingDirectory": portable_path(package),
    "derivedDataPath": portable_path(derived_data),
    "command": command,
    "commandSHA256": hashlib.sha256(command.encode()).hexdigest(),
}
pathlib.Path(output).write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY

    if [ ! -d "$PACKAGE_PATH" ] || [ ! -f "$PACKAGE_MANIFEST" ]; then
        : >"$stdout"
        printf 'nested package is missing: %s\n' "$PACKAGE_PATH" >"$stderr"
        status="unavailable"
        diagnostic="missing-package-path"
        exit_code=2
    elif [ "$TOOLCHAIN_STATUS" -ne 0 ]; then
        : >"$stdout"
        cp "$TOOLCHAIN_LOG" "$stderr"
        status="unavailable"
        diagnostic="xcodebuild-unavailable"
        exit_code="$TOOLCHAIN_STATUS"
    else
        set +e
        (
            cd "$PACKAGE_PATH"
            if [ -n "${target:-}" ]; then
                "$XCODEBUILD" -scheme "$SCHEME" -target "$target" -sdk "$sdk" -destination "$destination" \
                    -derivedDataPath "$derived_data" "$action"
            else
                "$XCODEBUILD" -scheme "$SCHEME" -sdk "$sdk" -destination "$destination" \
                    -derivedDataPath "$derived_data" "$action"
            fi
        ) >"$stdout" 2>"$stderr"
        exit_code=$?
        set -e
        if [ ! -s "$stdout" ] && [ ! -s "$stderr" ]; then
            status="unavailable"
            diagnostic="missing-command-logs"
        elif [ "$exit_code" -eq 0 ]; then
            status="succeeded"
            diagnostic="none"
        elif grep -Eqi 'unable to find a destination|not available|ineligible destination|platform .* is not supported' "$stdout" "$stderr"; then
            status="unavailable"
            diagnostic="destination-unavailable"
        else
            status="failed"
            diagnostic="xcodebuild-failed"
        fi
    fi

    write_result "$result" "$platform" "$sdk" "$destination" "$action" "$status" "$diagnostic" "$exit_code" "$stdout" "$stderr" "$command" "$fixture"
    [ "$status" = "succeeded" ] || overall_exit=2
done

python3 - "$RUN_ROOT/matrix.json" "$RUN_ID" "$RESULTS_ROOT" <<'PY'
import json
import pathlib
import sys

output, run_id, root = sys.argv[1:]
results = [json.loads(path.read_text(encoding="utf-8")) for path in sorted(pathlib.Path(root).glob("*/result.json"))]
value = {
    "schema": "PublicWorkflowPlatformMatrixV1",
    "runID": run_id,
    "results": results,
    "admittedPlatforms": [result["platform"] for result in results if result["status"] == "succeeded"],
    "finalStatus": "success" if results and all(result["status"] == "succeeded" for result in results) else "unavailable",
}
pathlib.Path(output).write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY
cp "$RUN_ROOT/matrix.json" "$REPORT_ROOT/platform-matrix.json"
echo "public-workflow platform matrix: retained run $RUN_ID at $RUN_ROOT" >&2
exit "$overall_exit"
