#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/public-workflow-conformance.yml"
PORTABLE_CONTRACT="$ROOT/Tests/Fixtures/PublicWorkflowConformance/CI/PORTABLE_INVOCATION.md"
RELEASE_QUALIFICATION="$ROOT/scripts/run_release_qualification.sh"

require() {
    grep -Fq -- "$1" "$WORKFLOW" || { echo "missing public-workflow CI contract: $1" >&2; exit 1; }
}

require "runs-on: macos-15"
require "schedule:"
require "cron: '30 2 * * *'"
require "check-head:"
require "listWorkflowRuns"
require "workflow_id: 'public-workflow-conformance.yml'"
require "run_expensive"
require "scripts/run_public_workflow_support_gate.sh --hosted-ci"
require "Run correlated public-workflow validation"
require "GITHUB_RUN_ID"
require "GITHUB_RUN_ATTEMPT"
require "if: always()"
require "actions/upload-artifact@v6"
require "public-workflow-evidence-\${{ github.run_id }}"
! grep -Fq -- "swift run" "$WORKFLOW" || { echo "aggregate workflow must not use swift run" >&2; exit 1; }
! grep -Fq -- "pull_request:" "$WORKFLOW" || { echo "public workflow must not run on pull requests" >&2; exit 1; }
[ -f "$PORTABLE_CONTRACT" ] || { echo "missing portable public-workflow invocation contract" >&2; exit 1; }
grep -Fq -- "project-relative" "$PORTABLE_CONTRACT" || { echo "portable invocation contract lacks project-relative paths" >&2; exit 1; }
[ -f "$RELEASE_QUALIFICATION" ] || { echo "missing local release contract" >&2; exit 1; }
grep -Fq -- "make public-workflow-release-check" "$RELEASE_QUALIFICATION" || { echo "local release path omits public-workflow gate" >&2; exit 1; }
! grep -Fq -- "public-workflow-release-check --hosted-ci" "$RELEASE_QUALIFICATION" || { echo "local release path must retain diagnostic authority" >&2; exit 1; }

echo "public-workflow CI contract checks passed"
