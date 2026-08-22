#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
MAKEFILE="$ROOT/Makefile"
RELEASE_QUALIFICATION="$ROOT/scripts/run_release_qualification.sh"
WORKFLOW="$ROOT/.github/workflows/temporal-symmetry-conformance.yml"
CHECK="$ROOT/scripts/check_temporal_symmetry_release.sh"

require() {
    grep -Fq -- "$1" "$2" || {
        echo "missing release contract: $1 in $2" >&2
        exit 1
    }
}

require "temporal-symmetry-release-check:" "$MAKEFILE"
require "check_temporal_symmetry_release.sh" "$MAKEFILE"
require "make temporal-symmetry-release-check" "$RELEASE_QUALIFICATION"
require "make temporal-symmetry-release-check" "$WORKFLOW"
require 'case "$status" in' "$CHECK"
require '"success"' "$CHECK"
require '"blocked"' "$CHECK"
require '"unavailable"' "$CHECK"
require '"admitted"' "$CHECK"
require "current-support-admission.json" "$CHECK"
require "TemporalSymmetryRegisterTests" "$CHECK"
require "support-surface.json" "$CHECK"

echo "temporal-symmetry release checks passed"
