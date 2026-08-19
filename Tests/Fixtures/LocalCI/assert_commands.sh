#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
makefile="$root/Makefile"
pr_runner="$root/scripts/run_pr_validation.sh"
smoke_runner="$root/scripts/run_pr_smoke_tests.sh"
release_runner="$root/scripts/run_release_qualification.sh"
local_runner="$root/scripts/run_ci_locally.sh"

require() {
    local file="$1"
    local expected="$2"
    grep -Fq -- "$expected" "$file" || {
        echo "missing local CI contract in $file: $expected" >&2
        exit 1
    }
}

forbid() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq -- "$unexpected" "$file"; then
        echo "forbidden local CI contract in $file: $unexpected" >&2
        exit 1
    fi
}

require "$makefile" "ci-pr:"
require "$makefile" "ci-release-qualification:"
require "$makefile" "temporal-symmetry-release-check:"
require "$makefile" "public-workflow-release-check:"

require "$pr_runner" "Tests/Fixtures/LocalCI/assert_commands.sh"
require "$pr_runner" "Tests/Fixtures/ReleaseCodeCheck/assert_workflow.sh"
require "$pr_runner" "./scripts/lint-zero-new.sh"
require "$pr_runner" "./scripts/run_pr_smoke_tests.sh"
require "$pr_runner" "swift build"
require "$pr_runner" "swift build --target SwiftTLAMacros"
require "$pr_runner" "make examples"
forbid "$pr_runner" "swift test --enable-code-coverage"
forbid "$pr_runner" "core-conformance"
forbid "$pr_runner" "temporal-symmetry"
forbid "$pr_runner" "public-workflow"

require "$smoke_runner" "local-validation.sh swiftpm-test"
require "$smoke_runner" "GeneratedStateMachineTests"
require "$smoke_runner" "NestedComposableMacroConformanceTests"
require "$smoke_runner" "SpecParserTests"
forbid "$smoke_runner" "UpstreamParityTests"
forbid "$smoke_runner" "CoreConformance"
forbid "$smoke_runner" "TLCTemporal"

require "$local_runner" 'exec "$(dirname "$0")/run_pr_validation.sh"'

require "$release_runner" "Tests/Fixtures/ReleaseCodeCheck/assert_workflow.sh"
require "$release_runner" "./scripts/lint-zero-new.sh"
require "$release_runner" "swift test"
require "$release_runner" "swift test --enable-code-coverage"
require "$release_runner" "swift build"
require "$release_runner" "swift build --target SwiftTLAMacros"
require "$release_runner" "make examples"
require "$release_runner" "Tests/Fixtures/CoreConformance/CI/assert_workflow.sh"
require "$release_runner" "Tests/Fixtures/TemporalSymmetryConformance/CI/assert_workflow.sh"
require "$release_runner" "make temporal-symmetry-release-check"
require "$release_runner" "make public-workflow-release-check"

echo "local CI command contracts passed"
