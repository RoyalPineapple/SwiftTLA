#!/usr/bin/env bash
set -euo pipefail

output=".build/public-workflow-support-gate"
hosted=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="${2:?missing output}"; shift 2 ;;
    --hosted-ci) hosted="--hosted-ci"; shift ;;
    *) echo "Usage: $0 [--output <directory>] [--hosted-ci]" >&2; exit 2 ;;
  esac
done

derived_data="$output/cli-derived-data"
xcodebuild -scheme tlc-validate -sdk macosx -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" build
"$derived_data/Build/Products/Debug/tlc-validate" public-workflow --output "$output" $hosted
