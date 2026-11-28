#!/usr/bin/env bash
set -euo pipefail

# Called only through local-validation.sh's lock and memory watchdog.
# First use installs the existing pinned build's system prerequisites.
root="$PWD"
metadata=$(python3 scripts/verify-tlaps-build-inputs.py \
    Verification/Semantics/proof-toolchain.json Tools/TLAPS/packaging.patch)
common_git_dir=$(git rev-parse --git-common-dir)
receipt_root="$common_git_dir/swifttla-proof-evidence/pinned-local-toolchain"
mkdir -p "$receipt_root"
export PROOF_EVIDENCE
PROOF_EVIDENCE=$(mktemp -d "$receipt_root/bootstrap.XXXXXX")
printf 'Pinned toolchain evidence: %s\n' "$PROOF_EVIDENCE"

if [[ -f .build/pinned-tlaps/tlapm/bin/tlapm ]]; then
    export PROOF_CACHE_HIT=true
else
    source_commit=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["sourceCommit"])' <<< "$metadata")
    compiler=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["ocamlCompiler"])' <<< "$metadata")
    repository_commit=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["opamRepositoryCommit"])' <<< "$metadata")
    brew install opam wget gcc zlib
    mkdir -p .build
    if [[ ! -e .build/tlaps-source ]]; then
        git clone --no-checkout https://github.com/tlaplus/tlapm.git .build/tlaps-source
        git -C .build/tlaps-source checkout --detach "$source_commit"
    fi
    test "$(git -C .build/tlaps-source rev-parse HEAD)" = "$source_commit"
    test -z "$(git -C .build/tlaps-source status --porcelain)"
    export OPAMROOT="$root/.build/proof-opam"
    if [[ ! -f "$OPAMROOT/config" ]]; then
        opam init --bare --no-setup --disable-sandboxing --yes default \
            "git+https://github.com/ocaml/opam-repository.git#$repository_commit"
    fi
    grep -Fxq "    {\"git+https://github.com/ocaml/opam-repository.git#$repository_commit\"}" \
        "$OPAMROOT/repo/repos-config"
    if [[ ! -d "$OPAMROOT/proof-pinned" ]]; then
        opam switch create proof-pinned "$compiler" --yes --no-switch
    fi
    eval "$(opam env --switch=proof-pinned --set-switch)"
    test "$(ocamlc -version)" = "${compiler#ocaml-base-compiler.}"
    export PROOF_CACHE_HIT=false
fi

# Reuse the actual hosted builder, its full backend set, pins and integrity checks.
bash scripts/build-pinned-tlaps.sh
