#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo 'usage: bash scripts/check-language-proof-batch.sh <pinned-tlapm> <batch-file> <evidence-directory>' >&2
    exit 64
fi
proof_tool="$1"
batch="$2"
evidence="$3"
[[ -x "$proof_tool" && -f "$batch" ]] || exit 64
[[ ! -e "$evidence" && ! -L "$evidence" ]] || { echo 'proof batch evidence already exists' >&2; exit 64; }
mkdir -p "$evidence/sources"
"$proof_tool" --version > "$evidence/tlapm-version.txt"
grep -Fxq '941f894' "$evidence/tlapm-version.txt"
"$proof_tool" --config > "$evidence/tlapm-config.txt" 2>&1
proof_z3="$(dirname "$proof_tool")/../lib/tlapm/backends/bin/z3"
"$proof_z3" --version > "$evidence/z3-version.txt"
grep -Fxq 'Z3 version 4.15.4 - 64 bit' "$evidence/z3-version.txt"
shasum -a 256 "$proof_tool" "$proof_z3" > "$evidence/tool-binaries.sha256"
shasum -a 256 "$batch" scripts/check-language-proof-batch.sh > "$evidence/runner-inputs.sha256"
git rev-parse HEAD > "$evidence/source-sha.txt"
cp "$batch" "$evidence/batch.txt"
cp Verification/Semantics/*.tla "$evidence/sources/"
shasum -a 256 Verification/Semantics/*.tla > "$evidence/proof-sources.sha256"
printf 'module\tresult\n' > "$evidence/results.tsv"

failed=0
checked=0
seen=$'\n'
while IFS= read -r module || [[ -n "$module" ]]; do
    [[ -n "$module" && "$module" != \#* ]] || continue
    [[ "$module" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo 'invalid proof module in batch' >&2; exit 64; }
    [[ "$seen" != *$'\n'"$module"$'\n'* ]] || { echo 'duplicate proof module in batch' >&2; exit 64; }
    seen+="$module"$'\n'
    source="Verification/Semantics/$module.tla"
    [[ -f "$source" ]] || { echo "missing proof module: $module" >&2; exit 64; }
    checked=$((checked + 1))
    if "$proof_tool" --nofp "$source" > "$evidence/$module.log" 2>&1 \
        && grep -Eq '^\[INFO\]: All [1-9][0-9]* obligations proved\.$' "$evidence/$module.log" \
        && ! grep -q '^\[ERROR\]' "$evidence/$module.log"; then
        printf '%s\tproved\n' "$module" | tee -a "$evidence/results.tsv"
    else
        printf '%s\tfailed\n' "$module" | tee -a "$evidence/results.tsv"
        failed=1
    fi
done < "$batch"
[[ "$checked" -gt 0 && "$failed" -eq 0 ]]
