#!/usr/bin/env bash

set -uo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
baseline_template="$project_root/.swiftlint-baseline.json"
config="$project_root/.swiftlint.yml"
baseline=$(mktemp "${TMPDIR:-/tmp}/swifttla-swiftlint-baseline.XXXXXX")
raw_report=$(mktemp "${TMPDIR:-/tmp}/swifttla-swiftlint-raw.XXXXXX")
new_report=$(mktemp "${TMPDIR:-/tmp}/swifttla-swiftlint-new.XXXXXX")

cleanup() {
    rm -f -- "$baseline" "$raw_report" "$new_report"
}
trap cleanup EXIT

jq --arg root "$project_root" '
    map(.violation.location.file |= gsub("file://__PROJECT_ROOT__"; "file://" + $root))
' "$baseline_template" > "$baseline"

swiftlint lint \
    --strict \
    --config "$config" \
    --force-exclude \
    --no-cache \
    --quiet \
    --reporter json \
    "$project_root" > "$raw_report" || true

swiftlint lint \
    --strict \
    --config "$config" \
    --force-exclude \
    --no-cache \
    --quiet \
    --reporter json \
    --baseline "$baseline" \
    "$project_root" > "$new_report" || true

baseline_count=$(jq 'length' "$baseline_template")
scanned_count=$(jq 'length' "$raw_report")
new_count=$(jq 'length' "$new_report")

printf 'SwiftLint legacy baseline: %s exact findings\n' "$baseline_count"
printf 'SwiftLint authored findings scanned: %s\n' "$scanned_count"
printf 'SwiftLint new findings: %s\n' "$new_count"

if [[ "$new_count" -ne 0 ]]; then
    jq -r '.[] | "\(.file):\(.line // 0): \(.rule_id): \(.reason)"' "$new_report"
    exit 1
fi
