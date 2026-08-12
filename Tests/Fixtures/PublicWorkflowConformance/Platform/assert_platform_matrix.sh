#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUNNER="$ROOT/scripts/run_public_workflow_platform_matrix.sh"
TMP="$(mktemp -d "$ROOT/.build/public-workflow-platform-contract.XXXXXX")"

context="$TMP/context.json"
python3 - "$context" <<'PY'
import json
import sys

digest = "a" * 64
provenance = {
    "caseID": "nested-package-macos",
    "moduleSHA256": digest,
    "cfgSHA256": digest,
    "argumentsSHA256": digest,
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
    "caseID": "nested-package-macos",
    "gateRunID": "11111111-1111-4111-8111-111111111111",
    "sourceInput": {"path": "Tests/Fixtures/PublicWorkflowConformance/Platform/assert_platform_matrix.sh", "sha256": digest},
    "configuration": {"path": "Packages/SwiftTLAVerified/Package.swift", "sha256": digest},
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
      .schema == "PublicWorkflowPlatformMatrixV1"
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
      and .results[0].correlation.caseID == "nested-package-macos"
      and .results[0].correlation.gateRunID == "11111111-1111-4111-8111-111111111111"
      and .results[0].fixtureBinding.evidence == .results[0].fixture
      and .results[0].stdoutBinding.evidence == .results[0].stdout
      and .results[0].stderrBinding.evidence == .results[0].stderr
    ' "$report" >/dev/null
}

single_platform='macos|macosx|platform=macOS|test'
expect_exit 2 env PUBLIC_WORKFLOW_PLATFORM_PACKAGE_PATH="$TMP/no-package" \
    PUBLIC_WORKFLOW_PLATFORM_MATRIX="$single_platform" "$RUNNER" --output "$TMP/missing-package" --context "$context"
assert_result "$TMP/missing-package/platform-matrix.json" unavailable missing-package-path

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

echo "public-workflow platform matrix checks passed"
