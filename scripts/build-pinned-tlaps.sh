#!/usr/bin/env bash
set -euo pipefail

project_root="$(pwd)"
pin="$project_root/Verification/Semantics/proof-toolchain.json"
patch="$project_root/Tools/TLAPS/packaging.patch"
source_root="$project_root/.build/tlaps-source"
tool_root="$project_root/.build/pinned-tlaps"
evidence="${PROOF_EVIDENCE:?proof evidence directory is required}"
metadata=$(python3 scripts/verify-tlaps-build-inputs.py "$pin" "$patch")
source_commit=$(jq -r .sourceCommit <<< "$metadata")
revision=$(jq -r .sourceRevision <<< "$metadata")
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64|Darwin-arm64) ;;
    *) echo 'Unsupported pinned proof-tool build platform' >&2; exit 64 ;;
esac
identity=$(shasum -a 256 "$pin" "$patch" "$project_root/scripts/build-pinned-tlaps.sh" \
    "$project_root/scripts/verify-tlaps-build-inputs.py" \
    "$project_root/.github/actions/setup-pinned-tlaps/action.yml" | shasum -a 256 | awk '{print $1}')

if [ "${PROOF_CACHE_HIT:-false}" != true ]; then
    test "$(git -C "$source_root" rev-parse HEAD)" = "$source_commit"
    test -z "$(git -C "$source_root" status --porcelain)"
    git -C "$source_root" apply --check "$patch"
    git -C "$source_root" apply "$patch"
    # Keep upstream's full backend build: existing proofs require Isabelle and PTL/LS4.
    mkdir -p "$tool_root/build-record"
    cp "$pin" "$tool_root/build-record/proof-toolchain.json"
    git -C "$source_root" diff --binary > "$tool_root/build-record/packaging.patch"
    shasum -a 256 "$pin" "$patch" > "$tool_root/build-record/build-inputs.sha256"
    (
        cd "$source_root"
        eval "$(opam env)"
        make opam-deps
        make opam-deps-opt
        opam list --installed --columns=name,version > "$tool_root/build-record/opam-packages.txt"
        opam switch export "$tool_root/build-record/opam-switch.export"
        ocamlc -version > "$tool_root/build-record/ocaml-version.txt"
        opam --version > "$tool_root/build-record/opam-version.txt"
        make release "RELEASE_VERSION=swifttla-$revision"
        archive="_build/tlapm-swifttla-$revision-$(uname -m)-$([ "$(uname -s)" = Linux ] && echo linux-gnu || echo darwin).tar.gz"
        shasum -a 256 "$archive" > "$tool_root/build-record/built-archive.sha256"
        tar -xzf "$archive" -C "$tool_root"
    )
    printf '%s\n' "$identity" > "$tool_root/build-record/identity.txt"
    uname -a > "$tool_root/build-record/host.txt"
    cc --version >> "$tool_root/build-record/host.txt"
    # OS/SDK and build-tool behavior remain trusted, not bit-for-bit reproducibility claims.
    (
        cd "$tool_root"
        find tlapm build-record -type f -exec shasum -a 256 {} \; > contents.sha256
    )
fi

test "$(cat "$tool_root/build-record/identity.txt")" = "$identity"
(cd "$tool_root" && shasum -a 256 -c contents.sha256)
mkdir -p "$evidence"
cp -R "$tool_root/build-record" "$evidence/"
cp "$tool_root/contents.sha256" "$evidence/"
"$tool_root/tlapm/bin/tlapm" --version > "$evidence/tlapm-version.txt"
# The packaging-only patch remains visible in the tool's version and receipt.
grep -Eq "^${revision}(-dirty)?$" "$evidence/tlapm-version.txt"
"$tool_root/tlapm/lib/tlapm/backends/bin/z3" --version > "$evidence/z3-version.txt"
grep -Fxq 'Z3 version 4.15.4 - 64 bit' "$evidence/z3-version.txt"
"$tool_root/tlapm/bin/tlapm" --config > "$evidence/tlapm-config.txt" 2>&1
