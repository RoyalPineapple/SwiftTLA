#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUNNER="$ROOT/scripts/run_public_workflow_platform_matrix.sh"
TMP="$(mktemp -d "$ROOT/.build/public-workflow-platform-contract.XXXXXX")"

context="$TMP/context.json"
python3 - "$context" "$ROOT" <<'PY'
import hashlib
import json
import pathlib
import sys

digest = "a" * 64
root = pathlib.Path(sys.argv[2])
source_path = "Tests/Fixtures/PublicWorkflowConformance/Platform/assert_platform_matrix.sh"
configuration_path = "Package.swift"
source_digest = hashlib.sha256((root / source_path).read_bytes()).hexdigest()
configuration_digest = hashlib.sha256((root / configuration_path).read_bytes()).hexdigest()
provenance = {
    "caseID": "public-library-macos",
    "moduleSHA256": source_digest,
    "cfgSHA256": configuration_digest,
    "argumentsSHA256": hashlib.sha256(json.dumps([["xcodebuild", "-scheme", "SwiftTLA-Package", "-target", "SwiftTLA", "-sdk", "macosx", "-destination", "platform=macOS", "build"]], separators=(",", ":")).encode()).hexdigest(),
    "tlcTag": "v1.8.0",
    "tlcCommit": "30cc3601321c3fc02e044d0ecb5c58d8921e18df",
    "tlcJarSHA256": digest,
    "javaDistribution": "Eclipse Temurin",
    "javaVersion": "17.0.19+10",
    "javaArchiveSHA256": digest,
    "bridgeClass": "org.swifttla.conformance.LosslessStateWriter",
    "bridgeSourceSHA256": digest,
    "bridgeBinarySHA256": digest,
}
value = {
    "caseID": "public-library-macos",
    "gateRunID": "11111111-1111-4111-8111-111111111111",
    "sourceInput": {"path": source_path, "sha256": source_digest},
    "configuration": {"path": configuration_path, "sha256": configuration_digest},
    "provenance": provenance,
}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(value))
PY

expect_exit() {
    local expected="$1"
    shift
    set +e
    "$@" >"$TMP/stdout" 2>"$TMP/stderr"
    local exit_code=$?
    set -e
    if [ "$exit_code" -ne "$expected" ]; then
        echo "expected exit $expected, got $exit_code: $*" >&2
        cat "$TMP/stderr" >&2
        exit 1
    fi
}

assert_result() {
    local report="$1"
    local expected_status="$2"
    local expected_diagnostic="$3"
    jq -e --arg status "$expected_status" --arg diagnostic "$expected_diagnostic" '
      .schema == "PublicWorkflowPlatformMatrix"
      and .finalStatus != "success"
      and (.results | length == 1)
      and .results[0].status == $status
      and (if $status == "unavailable" then .results[0].exitCode == null else .results[0].exitCode != 0 end)
      and (.results[0].command | contains("xcodebuild"))
      and (.results[0].sdk | length > 0)
      and (.results[0].destination | length > 0)
      and (.results[0].xcodeVersion | length > 0)
      and (.results[0].fixture.path | startswith(".build/"))
      and (.results[0].stdout.path | startswith(".build/"))
      and (.results[0].stderr.path | startswith(".build/"))
      and .results[0].correlation.caseID == "public-library-macos"
      and .results[0].correlation.gateRunID == "11111111-1111-4111-8111-111111111111"
      and .results[0].fixtureBinding.evidence == .results[0].fixture
      and .results[0].stdoutBinding.evidence == .results[0].stdout
      and .results[0].stderrBinding.evidence == .results[0].stderr
      and .results[0].execution.authority == "diagnostic"
      and (.results[0].execution.metadata.path | startswith(".build/"))
    ' "$report" >/dev/null
    local fixture_path
    fixture_path="$(jq -r '.results[0].fixture.path' "$report")"
    jq -e '
      ((.workingDirectory == ".") or (.workingDirectory | startswith(".build/")) or (.workingDirectory | startswith("/")))
      and (.workingDirectory | contains("../") | not)
      and (.derivedDataPath | startswith(".build/"))
      and (.command | contains("xcodebuild"))
      and (.commandSHA256 | test("^[0-9a-f]{64}$"))
    ' "$ROOT/$fixture_path" >/dev/null
}

single_platform='macos|macosx|platform=macOS|build|SwiftTLA'
expect_exit 2 env PUBLIC_WORKFLOW_PLATFORM_PACKAGE_PATH="$TMP/no-package" \
    PUBLIC_WORKFLOW_PLATFORM_MATRIX="$single_platform" "$RUNNER" --output "$TMP/missing-package" --context "$context"
assert_result "$TMP/missing-package/platform-matrix.json" unavailable missing-package-path

expect_exit 2 env PUBLIC_WORKFLOW_PLATFORM_PACKAGE_PATH="$TMP/configured-missing" \
    PUBLIC_WORKFLOW_PLATFORM_MATRIX="$single_platform" "$RUNNER" --output "$TMP/configured-package" --context "$context"
assert_result "$TMP/configured-package/platform-matrix.json" unavailable missing-package-path

fake_destination="$TMP/fake-destination-xcodebuild"
printf '%s\n' '#!/bin/bash' 'if [ "$1" = "-version" ]; then echo "Xcode Fake"; exit 0; fi' 'echo "Unable to find a destination matching the provided destination specifier" >&2' 'exit 70' > "$fake_destination"
chmod +x "$fake_destination"
expect_exit 2 env PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD="$fake_destination" \
    PUBLIC_WORKFLOW_PLATFORM_MATRIX="$single_platform" "$RUNNER" --output "$TMP/unavailable-destination" --context "$context"
assert_result "$TMP/unavailable-destination/platform-matrix.json" unavailable destination-unavailable

fake_failure="$TMP/fake-failed-xcodebuild"
printf '%s\n' '#!/bin/bash' 'if [ "$1" = "-version" ]; then echo "Xcode Fake"; exit 0; fi' 'echo "compile failure" >&2' 'exit 65' > "$fake_failure"
chmod +x "$fake_failure"
expect_exit 2 env PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD="$fake_failure" \
    PUBLIC_WORKFLOW_PLATFORM_MATRIX="$single_platform" "$RUNNER" --output "$TMP/failed-build" --context "$context"
assert_result "$TMP/failed-build/platform-matrix.json" failed xcodebuild-failed

fake_silent="$TMP/fake-silent-xcodebuild"
printf '%s\n' '#!/bin/bash' 'if [ "$1" = "-version" ]; then echo "Xcode Fake"; exit 0; fi' 'exit 0' > "$fake_silent"
chmod +x "$fake_silent"
expect_exit 2 env PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD="$fake_silent" \
    PUBLIC_WORKFLOW_PLATFORM_MATRIX="$single_platform" "$RUNNER" --output "$TMP/missing-logs" --context "$context"
assert_result "$TMP/missing-logs/platform-matrix.json" unavailable missing-command-logs

fake_success="$TMP/fake-success-xcodebuild"
printf '%s\n' '#!/bin/bash' 'if [ "$1" = "-version" ]; then echo "Xcode Fake"; exit 0; fi' 'echo "build succeeded"' 'exit 0' > "$fake_success"
chmod +x "$fake_success"
spoofed="$TMP/spoofed-env"
expect_exit 0 env GITHUB_ACTIONS=true GITHUB_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    GITHUB_REPOSITORY=RoyalPineapple/SwiftTLA GITHUB_WORKFLOW='Public Workflow Conformance' \
    GITHUB_REF=refs/heads/main GITHUB_RUN_ID=123 GITHUB_RUN_ATTEMPT=1 GITHUB_JOB=public-workflow \
    GITHUB_SERVER_URL=https://github.com PUBLIC_WORKFLOW_PLATFORM_XCODEBUILD="$fake_success" \
    PUBLIC_WORKFLOW_PLATFORM_MATRIX="$single_platform" "$RUNNER" --output "$spoofed" --context "$context"
jq -e '.results[0].execution.authority == "diagnostic" and (.results[0].execution.identity == null)' \
    "$spoofed/platform-matrix.json" >/dev/null

zero_context="$TMP/zero-context.json"
python3 - "$zero_context" <<'PY'
import json
import pathlib
import sys
value = json.loads(pathlib.Path(sys.argv[1]).with_name("context.json").read_text())
value["sourceInput"]["sha256"] = "0" * 64
pathlib.Path(sys.argv[1]).write_text(json.dumps(value))
PY
expect_exit 2 "$RUNNER" --output "$TMP/zero-context" --context "$zero_context"

arguments_context="$TMP/arguments-context.json"
python3 - "$arguments_context" <<'PY'
import json
import pathlib
import sys
value = json.loads(pathlib.Path(sys.argv[1]).with_name("context.json").read_text())
value["provenance"]["argumentsSHA256"] = "f" * 64
pathlib.Path(sys.argv[1]).write_text(json.dumps(value))
PY
expect_exit 2 "$RUNNER" --output "$TMP/arguments-context" --context "$arguments_context"

echo "public-workflow platform matrix checks passed"
