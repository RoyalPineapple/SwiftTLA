#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
jq -r '.cases[] | [[.id, .module, .moduleSHA256], [.id, .configuration, .cfgSHA256]][] | @tsv' \
  "$root/Verification/FiniteGraph/cases.json" |
while IFS=$'\t' read -r case_id relative_path expected; do
  reference="$root/Verification/FiniteGraph/fixtures/$relative_path"
  test -f "$reference"
  actual=$(shasum -a 256 "$reference")
  actual=${actual%% *}
  if [ "$actual" != "$expected" ]; then
    echo "$case_id: digest mismatch for $relative_path: expected $expected, actual $actual" >&2
    exit 1
  fi
done
